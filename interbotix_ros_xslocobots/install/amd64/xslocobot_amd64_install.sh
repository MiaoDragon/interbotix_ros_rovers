#!/usr/bin/env bash

# USAGE: ./xslocobot_amd64_install.sh [-h][-d DISTRO][-p PATH][-b BASE_TYPE][-n]
#
# Install the Interbotix X-Series LoCoBot packages and their dependencies.

set -e

OFF='\033[0m'
RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'

BOLD=$(tput bold)
NORM=$(tput sgr0)

ERR="${RED}${BOLD}"
RRE="${NORM}${OFF}"

PROMPT="> "

ALL_VALID_DISTROS=('melodic' 'noetic' 'galactic')
ROS1_VALID_DISTROS=('melodic' 'noetic')
ROS2_VALID_DISTROS=('galactic')

BIONIC_VALID_DISTROS=('melodic')
FOCAL_VALID_DISTROS=('noetic' 'galactic')

VALID_BASE_TYPES=('kobuki' 'create3')

NONINTERACTIVE=false
DISTRO_SET_FROM_CL=false
INSTALL_PATH=~/interbotix_ws
REALSENSE_WS=~/realsense_ws
APRILTAG_WS=~/apriltag_ws
BRIDGE_WS=~/ros1_bridge_ws
BRIDGE_MSGS_ROS1_WS=~/create3_ros1_ws
BRIDGE_MSGS_ROS2_WS=~/create3_ros2_ws

_usage="${BOLD}USAGE: ./xslocobot_amd64_install.sh [-h][-d DISTRO][-p PATH][-b BASE_TYPE][-n]${NORM}

Install the Interbotix X-Series LoCoBot packages and their dependencies.

Options:

  -h              Display this help message and quit

  -d DISTRO       Install the DISTRO ROS distro compatible with your Ubuntu version. See
                  'https://github.com/Interbotix/.github/blob/main/SECURITY.md' for the list of
                  supported distributions. If not given, installs the ROS 1 Distro compatible with
                  your Ubuntu version.

  -p PATH         Sets the absolute install location for the Interbotix workspace. If not specified,
                  the Interbotix workspace directory will default to '~/interbotix_ws'.

  -b BASE_TYPE    Sets the base type for the robot, either 'kobuki' or 'create3'. If not specified,
                  the default of 'create3' will be used. Note that the Create 3 is not compatible with
                  Ubuntu 18.04 or ROS 1 Melodic.

  -n              Install all packages and dependencies without prompting. This is useful if
                  you're running this script in a non-interactive terminal like when building a
                  Docker image.

Examples:

  ./xslocobot_amd64_install.sh ${BOLD}-h${NORM}
    This will display this help message and quit.

  ./xslocobot_amd64_install.sh
    This will install just the ROS 1 distro compatible with your Ubuntu version. It will prompt you
    to ask if you want to install certain packages and dependencies.

  ./xslocobot_amd64_install.sh ${BOLD}-d noetic${NORM}
    This will install ROS 1 Noetic assuming that your Ubuntu version is compatible.

  ./xslocobot_amd64_install.sh ${BOLD}-b kobuki${NORM}
    This will install packages for the kobuki base depending on your ROS distro and configure your
    environment accordingly.

  ./xslocobot_amd64_install.sh ${BOLD}-n${NORM}
    Skip prompts and install all packages and dependencies.

  ./xslocobot_amd64_install.sh ${BOLD}-d galactic${NORM}
    Install ROS 2 Galactic assuming that your Ubuntu version is compatible.

  ./xslocobot_amd64_install.sh ${BOLD}-d galactic -n${NORM}
    Install ROS 2 Galactic and all packages and dependencies.

  ./xslocobot_amd64_install.sh ${BOLD}-p ~/custom_ws${NORM}
    Installs the Interbotix packages under the '~/custom_ws' path."

function help() {
  # print usage
  cat << EOF
$_usage
EOF
}

# https://stackoverflow.com/a/8574392/16179107
function contains_element () {
  # check if an element is in an array
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

function failed() {
  # Log error and quit with a failed exit code
  echo -e "${ERR}[ERROR] $@${RRE}"
  echo -e "${ERR}[ERROR] Interbotix Installation Failed!${RRE}"
  exit 1
}

function validate_distro() {
  # check if chosen distro is valid and set ROS major version
  if contains_element $ROS_DISTRO_TO_INSTALL "${ALL_VALID_DISTROS[@]}"; then
    if contains_element $ROS_DISTRO_TO_INSTALL "${ROS1_VALID_DISTROS[@]}"; then
      # Supported ROS1 distros
      ROS_VERSION_TO_INSTALL=1
    elif contains_element $ROS_DISTRO_TO_INSTALL "${ROS2_VALID_DISTROS[@]}"; then
      # Supported ROS2 distros
      ROS_VERSION_TO_INSTALL=2
    else
      # For cases where it passes the first check but somehow fails the second check
      failed "Something went wrong."
    fi
    ROS_DISTRO_TO_INSTALL=$ROS_DISTRO_TO_INSTALL
    echo -e "${GRN}${BOLD}Chosen Version: ROS ${ROS_VERSION_TO_INSTALL} $ROS_DISTRO_TO_INSTALL${NORM}${OFF}"
    return 0
  else
    failed "'$ROS_DISTRO_TO_INSTALL' is not a valid ROS Distribution. Choose one of: "${ALL_VALID_DISTROS[@]}""
  fi
}

function validate_base_type() {
  if [ -z "$BASE_TYPE" ]; then
    failed "You must specify a base type using the '-b' flag followed by one of: "${VALID_BASE_TYPES[@]}""
  fi
  if contains_element $BASE_TYPE "${VALID_BASE_TYPES[@]}"; then
    :
  else
    failed "Base type '$BASE_TYPE' is not valid. Choose one of: "${VALID_BASE_TYPES[@]}""
  fi
}

function check_ubuntu_version() {
 # check if the chosen distribution is compatible with the Ubuntu version
  case $UBUNTU_VERSION in

    18.04 )
      if contains_element $ROS_DISTRO_TO_INSTALL "${BIONIC_VALID_DISTROS[@]}"; then
        PY_VERSION=2
      else
        failed "Chosen ROS distribution '$ROS_DISTRO_TO_INSTALL' is not supported on Ubuntu ${UBUNTU_VERSION}."
      fi
      ;;

    20.04 )
      if contains_element $ROS_DISTRO_TO_INSTALL "${FOCAL_VALID_DISTROS[@]}"; then
        PY_VERSION=3
      else
        failed "Chosen ROS distribution '$ROS_DISTRO_TO_INSTALL' is not supported on Ubuntu ${UBUNTU_VERSION}."
      fi
      ;;

    *)
      failed "Something went wrong."
      ;;

  esac
}

function install_essential_packages() {
  # Install necessary core packages
  sudo apt -y install openssh-server curl
  if [ $ROS_VERSION_TO_INSTALL == 2 ]; then
    sudo pip3 install transforms3d
  fi
  if [ $PY_VERSION == 2 ]; then
    sudo apt -y install python-pip
    sudo -H pip install modern_robotics six
  elif [ $PY_VERSION == 3 ]; then
    sudo apt -y install python3-pip
    sudo -H pip3 install modern_robotics six
  else
    failed "Something went wrong."
  fi
}

function install_ros1() {
  # Installs ROS 1
  # Step 1: Install ROS 1
  if [ $(dpkg-query -W -f='${Status}' ros-$ROS_DISTRO_TO_INSTALL-desktop-full 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    echo -e "${GRN}Installing ROS1 $ROS_DISTRO_TO_INSTALL...${OFF}"
    sudo sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list'
    curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | sudo apt-key add -
    sudo apt update
    sudo apt -y install ros-$ROS_DISTRO_TO_INSTALL-desktop-full
    if [ -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
      sudo rm /etc/ros/rosdep/sources.list.d/20-default.list
    fi
    if [ $PY_VERSION == 2 ]; then
      sudo apt -y install python-rosdep python-rosinstall python-rosinstall-generator python-wstool build-essential
    else
      sudo apt -y install python3-rosdep python3-rosinstall python3-rosinstall-generator python3-wstool build-essential
    fi
    sudo rosdep init
    rosdep update
    echo "source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash" >> ~/.bashrc
  else
    echo "ros-$ROS_DISTRO_TO_INSTALL-desktop-full is already installed!"
  fi
  source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash
}

function install_ros2() {
  # Installs ROS 2
  if [ $(dpkg-query -W -f='${Status}' ros-$ROS_DISTRO_TO_INSTALL-desktop 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    echo -e "${GRN}Installing ROS 2 $ROS_DISTRO_TO_INSTALL desktop...${OFF}"
    sudo apt install -y software-properties-common
    sudo add-apt-repository universe
    sudo apt install -y curl gnupg lsb-release
    sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(source /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
    sudo apt update
    sudo apt install -y ros-$ROS_DISTRO_TO_INSTALL-desktop
    if [ -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
      sudo rm /etc/ros/rosdep/sources.list.d/20-default.list
    fi
    sudo apt -y install python3-rosdep python3-rosinstall python3-rosinstall-generator python3-wstool build-essential python3-colcon-common-extensions
    sudo rosdep init
    rosdep update
    if [[ $ROS_VERSION_TO_INSTALL == 2 ]]; then
      echo "source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash" >> ~/.bashrc
      source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash
    fi
  else
    echo "ros-$ROS_DISTRO_TO_INSTALL-desktop-full is already installed!"
  fi
}

function install_perception_ros2() {
  # Step 2: Install Realsense packages

  # Step 2A: Install librealsense2
  if [ $(dpkg-query -W -f='${Status}' librealsense2 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
    echo -e "${GRN}Installing librealsense2...${OFF}"
    sudo apt-key adv --keyserver keys.gnupg.net --recv-key F6E65AC044F831AC80A06380C8B3A55A6F3EFCDE || sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key F6E65AC044F831AC80A06380C8B3A55A6F3EFCDE
    sudo add-apt-repository "deb https://librealsense.intel.com/Debian/apt-repo $(lsb_release -sc) main" -u
    version="2.50.0-0~realsense0.6128"

    sudo apt -y install                   \
      librealsense2-udev-rules=${version} \
      librealsense2-dkms                  \
      librealsense2=${version}            \
      librealsense2-gl=${version}         \
      librealsense2-gl-dev=${version}     \
      librealsense2-gl-dbg=${version}     \
      librealsense2-net=${version}        \
      librealsense2-net-dev=${version}    \
      librealsense2-net-dbg=${version}    \
      librealsense2-utils=${version}      \
      librealsense2-dev=${version}        \
      librealsense2-dbg=${version}
    sudo apt-mark hold librealsense2*
  else
    echo "librealsense2 already installed!"
  fi

  # Step 2B: Install realsense2 ROS Wrapper
  if source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash && source $REALSENSE_WS/install/setup.bash && ros2 pkg list | grep -q realsense;then
    echo "${GRN}Installing RealSense ROS Wrapper...${OFF}"
    mkdir -p $REALSENSE_WS/src
    cd $REALSENSE_WS/src
    git clone https://github.com/IntelRealSense/realsense-ros.git -b 4.0.4
    cd $REALSENSE_WS
    rosdep install -i --from-path src --rosdistro $ROS_DISTRO_TO_INSTALL --skip-keys=librealsense2 -y
    if colcon build; then
      echo -e "${GRN}${BOLD}Realsense ROS Wrapper built successfully!${NORM}${OFF}"
      echo "source $REALSENSE_WS/install/setup.bash" >> ~/.bashrc
    else
      failed "Failed to build Realsense ROS Wrapper."
    fi
  else
    echo "RealSense ROS Wrapper already installed!"
  fi
  source $REALSENSE_WS/install/setup.bash

  # Step 3: Install apriltag ROS Wrapper
  if source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash && source $APRILTAG_WS/install/setup.bash && ros2 pkg list | grep -q apriltag; then
    echo -e "${GRN}${BOLD}Installing Apriltag ROS Wrapper...${NORM}${OFF}"
    mkdir -p $APRILTAG_WS/src
    cd $APRILTAG_WS/src
    git clone https://github.com/AprilRobotics/apriltag.git
    git clone https://github.com/Interbotix/apriltag_ros.git -b ros2-port
    cd $APRILTAG_WS
    rosdep install --from-paths src --ignore-src -r -y --rosdistro=$ROS_DISTRO_TO_INSTALL
    if colcon build; then
      echo -e "${GRN}${BOLD}Apriltag ROS Wrapper built successfully!${NORM}${OFF}"
      echo "source $APRILTAG_WS/install/setup.bash" >> ~/.bashrc
    else
      failed "Failed to build Apriltag ROS Wrapper."
    fi
  else
    echo "Apriltag ROS Wrapper already installed!"
  fi
  source $APRILTAG_WS/install/setup.bash
}

function install_locobot_ros1() {
  if source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash && source $INSTALL_PATH/devel/setup.bash && rospack list | grep -q interbotix_; then
    echo "Interbotix LoCoBot ROS packages already installed!"
  else
    echo -e "${GRN}Installing ROS packages for the Interbotix LoCoBot...${OFF}"
    cd $INSTALL_PATH/src
    git clone https://github.com/Interbotix/interbotix_ros_core.git -b $ROS_DISTRO_TO_INSTALL
    git clone https://github.com/Interbotix/interbotix_ros_rovers.git -b $ROS_DISTRO_TO_INSTALL
    git clone https://github.com/Interbotix/interbotix_ros_toolboxes.git -b $ROS_DISTRO_TO_INSTALL
    rm interbotix_ros_core/interbotix_ros_xseries/CATKIN_IGNORE
    rm interbotix_ros_toolboxes/interbotix_xs_toolbox/CATKIN_IGNORE
    rm interbotix_ros_toolboxes/interbotix_perception_toolbox/CATKIN_IGNORE
    rm interbotix_ros_toolboxes/interbotix_common_toolbox/interbotix_moveit_interface/CATKIN_IGNORE
    cd interbotix_ros_core/interbotix_ros_xseries/interbotix_xs_sdk
    sudo cp 99-interbotix-udev.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules && sudo udevadm trigger
    cd $INSTALL_PATH
    rosdep install --from-paths src --ignore-src -r -y --rosdistro=$ROS_DISTRO_TO_INSTALL
    source $BRIDGE_MSGS_ROS1_WS/install_isolated/setup.bash
    if catkin_make; then
      echo -e "${GRN}${BOLD}Interbotix LoCoBot ROS packages built successfully!${NORM}${OFF}"
      echo "source $INSTALL_PATH/devel/setup.bash" >> ~/.bashrc
      source $INSTALL_PATH/devel/setup.bash
    else
      failed "Failed to build packages for the Interbotix LoCoBot."
    fi
  fi
}

function install_locobot_ros2() {
  if source /opt/ros/$ROS_DISTRO_TO_INSTALL/setup.bash && source $INSTALL_PATH/install/setup.bash && ros2 pkg list | grep -q interbotix_;then
    echo "Interbotix LoCoBot ROS packages already installed!"
  else
    echo -e "${GRN}Installing ROS 2 packages for the Interbotix LoCoBot...${OFF}"
    cd $INSTALL_PATH/src
    git clone https://github.com/Interbotix/interbotix_ros_core.git -b $ROS_DISTRO_TO_INSTALL
    git clone https://github.com/Interbotix/interbotix_ros_rovers.git -b $ROS_DISTRO_TO_INSTALL
    git clone https://github.com/Interbotix/interbotix_ros_toolboxes.git -b $ROS_DISTRO_TO_INSTALL
    # TODO(lsinterbotix) remove below when moveit_visual_tools is available in apt repo
    git clone https://github.com/ros-planning/moveit_visual_tools.git -b ros2
    rm interbotix_ros_toolboxes/interbotix_perception_toolbox/COLCON_IGNORE
    rm interbotix_ros_toolboxes/interbotix_common_toolbox/interbotix_moveit_interface/COLCON_IGNORE
    rm interbotix_ros_toolboxes/interbotix_common_toolbox/interbotix_moveit_interface_msgs/COLCON_IGNORE
    cd interbotix_ros_core
    git submodule update --init interbotix_ros_xseries/dynamixel_workbench_toolbox
    git submodule update --init interbotix_ros_xseries/interbotix_xs_driver
    cd interbotix_ros_xseries/interbotix_xs_sdk
    sudo cp 99-interbotix-udev.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules && sudo udevadm trigger
    cd $INSTALL_PATH
    rosdep install --from-paths src --ignore-src -r -y --rosdistro=$ROS_DISTRO_TO_INSTALL
    if colcon build; then
      echo -e "${GRN}${BOLD}Interbotix LoCoBot ROS packages built successfully!${NORM}${OFF}"
      echo "source $INSTALL_PATH/install/setup.bash" >> ~/.bashrc
      source $INSTALL_PATH/install/setup.bash
    else
      failed "Failed to build packages for the Interbotix LoCoBot."
    fi
  fi
}

function install_kobuki_ros1() {
  # Install ROS 1 packages for the Kobuki base
  echo -e "${GRN}Installing Kobuki ROS 1 packages...${OFF}"
  cd $INSTALL_PATH/src
  # no noetic branch - install from melodic branch source instead
  git clone https://github.com/yujinrobot/kobuki -b melodic
  sudo apt -y install liborocos-kdl-dev
  git clone https://github.com/yujinrobot/yujin_ocs.git
  cd yujin_ocs
  # Remove unused packages from yujin_ocs repo
  sudo rm -rf                       \
    yocs_ar_marker_tracking         \
    yocs_ar_pair_approach           \
    yocs_ar_pair_tracking           \
    yocs_diff_drive_pose_controller \
    yocs_joyop                      \
    yocs_keyop                      \
    yocs_localization_manager       \
    yocs_math_toolkit               \
    yocs_navi_toolkit               \
    yocs_navigator                  \
    yocs_rapps                      \
    yocs_safety_controller          \
    yocs_virtual_sensor             \
    yocs_waypoint_provider          \
    yocs_waypoints_navi             \
    yujin_ocs
  cd ..
  git clone https://github.com/Slamtec/rplidar_ros.git
}

function install_kobuki_ros2() {
  # Install ROS 2 packages for the Kobuki base
  echo -e "${GRN}Installing Kobuki ROS 2 packages...${OFF}"
  cd $INSTALL_PATH/src
  git clone https://github.com/kobuki-base/kobuki_core.git
  git clone https://github.com/kobuki-base/velocity_smoother.git
  git clone https://github.com/kobuki-base/cmd_vel_mux.git
  git clone https://github.com/kobuki-base/kobuki_ros_interfaces.git
  git clone https://github.com/kobuki-base/kobuki_ros.git
}

function install_create3_ros1() {
  # Install packages required to run the Create 3 using ROS 1, including ros1_bridge.
  # We can only install Galactic due to hardware constraints - The intersection of compatibility
  # between ros1_bridge and the Create 3 is galactic & noetic
  # TODO(lsinterbotix) only run this if messages can't be found, otherwise we rebuild ros1_bridge
  cd $INSTALL_PATH/src
  git clone https://github.com/Interbotix/create3_sim_ros1.git -b ros1

  # This requires ROS2 to be installed.
  TEMP_ROS_DISTRO_TO_INSTALL=$ROS_DISTRO_TO_INSTALL # save ROS distro
  ROS_DISTRO_TO_INSTALL=galactic
  install_ros2
  ROS_DISTRO_TO_INSTALL=$TEMP_ROS_DISTRO_TO_INSTALL # reset ROS distro to one originally specified

  # Need to build both ROS 1 and ROS 2 version of the Create 3 messages
  # ROS 1
  mkdir -p $BRIDGE_MSGS_ROS1_WS/src
  cd $BRIDGE_MSGS_ROS1_WS/src
  git clone https://github.com/Interbotix/irobot_create_msgs_ros1.git -b ros1
  TEMP1=$(mktemp)
  echo ". /opt/ros/noetic/setup.bash && cd $BRIDGE_MSGS_ROS1_WS && catkin_make_isolated --install" > $TEMP1
  chmod a+x $TEMP1
  if ($TEMP1); then
    echo -e "${GRN}${BOLD}irobot_create_msgs for ROS 1 built successfully!${NORM}${OFF}"
  else
    failed "Failed to build irobot_create_msgs for ROS 1."
  fi

  # ROS 2
  mkdir -p $BRIDGE_MSGS_ROS2_WS/src
  cd $BRIDGE_MSGS_ROS2_WS/src
  git clone https://github.com/iRobotEducation/irobot_create_msgs.git -b galactic
  TEMP2=$(mktemp)
  echo ". /opt/ros/galactic/setup.bash && cd $BRIDGE_MSGS_ROS2_WS && colcon build" > $TEMP2
  chmod a+x $TEMP2
  if ($TEMP2); then
    echo -e "${GRN}${BOLD}irobot_create_msgs for ROS 2 built successfully!${NORM}${OFF}"
  else
    failed "Failed to build irobot_create_msgs for ROS 2."
  fi

  # With both versions of the messages built, ros1_bridge can be built
  mkdir -p $BRIDGE_WS/src
  cd $BRIDGE_WS/src
  git clone https://github.com/ros2/ros1_bridge.git -b galactic
  TEMP3=$(mktemp)
  echo ". /opt/ros/noetic/setup.bash && . /opt/ros/galactic/setup.bash && . $BRIDGE_MSGS_ROS1_WS/install_isolated/setup.bash && . $BRIDGE_MSGS_ROS2_WS/install/setup.bash && cd $BRIDGE_WS && colcon build --packages-select ros1_bridge --cmake-force-configure" > $TEMP3
  chmod a+x $TEMP3
  if ($TEMP3); then
    echo -e "${GRN}${BOLD}ros1_bridge built successfully!${NORM}${OFF}"
  else
    failed "Failed to build ros1_bridge."
  fi

  # Check that irobot_create_msgs exists in the built messages
  TEMP4=$(mktemp)
  echo ". /opt/ros/noetic/setup.bash && . /opt/ros/galactic/setup.bash && . $BRIDGE_MSGS_ROS1_WS/install_isolated/setup.bash && . $BRIDGE_MSGS_ROS2_WS/install/setup.bash && . $BRIDGE_WS/install/setup.bash && ros2 run ros1_bridge dynamic_bridge --print-pairs | grep -q 'irobot_create_msgs'" > $TEMP4
  chmod a+x $TEMP4
  if ($TEMP4); then
    echo -e "${GRN}${BOLD}ros1_bridge dynamic_bridge found irobot_create_msgs interfaces!${NORM}${OFF}"
  else
    failed "Something went wrong when building ros1_bridge. ros1_bridge dynamic_bridge can't find irobot_create_msgs."
  fi
  echo -e "export BRIDGE_WS=${BRIDGE_WS}" >> ~/.bashrc
  echo -e "export BRIDGE_MSGS_ROS1_WS=${BRIDGE_MSGS_ROS1_WS}" >> ~/.bashrc
  echo -e "export BRIDGE_MSGS_ROS2_WS=${BRIDGE_MSGS_ROS2_WS}" >> ~/.bashrc
  echo -e "source $BRIDGE_MSGS_ROS1_WS/install_isolated/setup.bash" >> ~/.bashrc
}

function install_create3_ros2() {
  # Install LoCoBot packages for the Create 3 base
  cd $INSTALL_PATH/src
  git clone https://github.com/iRobotEducation/irobot_create_msgs.git -b $ROS_DISTRO_TO_INSTALL
  git clone https://github.com/iRobotEducation/create3_sim.git -b $ROS_DISTRO_TO_INSTALL
}

function setup_env_vars() {
  # Setup Environment Variables
  if [ -z "$ROS_IP" ]; then
    echo "Setting up Environment Variables..."
    echo "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp" >> ~/.bashrc
    echo -e "export INTERBOTIX_XSLOCOBOT_BASE_TYPE=${BASE_TYPE}" >> ~/.bashrc
    echo 'export ROS_IP=$(echo `hostname -I | cut -d" " -f1`)' >> ~/.bashrc
    echo -e 'if [ -z "$ROS_IP" ]; then\n\texport ROS_IP=127.0.0.1\nfi' >> ~/.bashrc
  else
    echo "Environment variables already set!"
  fi
}

# parse command line arguments
while getopts 'hnb:d:p:' OPTION;
do
  case "$OPTION" in
    h) help && exit 0;;
    n) NONINTERACTIVE=true;;
    b) BASE_TYPE="$OPTARG";;
    d) ROS_DISTRO_TO_INSTALL="$OPTARG" && DISTRO_SET_FROM_CL=true;;
    p) INSTALL_PATH="$OPTARG";;
    *) echo "Unknown argument $OPTION" && help && exit 0;;
  esac
done
shift "$(($OPTIND -1))"

validate_base_type

if ! command -v lsb_release &> /dev/null; then
  sudo apt update
  sudo apt-get install -y lsb-release
fi

UBUNTU_VERSION="$(lsb_release -rs)"

# set default ROS distro before reading clargs
if [ "$DISTRO_SET_FROM_CL" = false ]; then
  if [ $UBUNTU_VERSION == "18.04" ]; then
    if [ $BASE_TYPE == "create3" ]; then
      failed "The iRobot Create 3 base is incompatible with Ubuntu 18.04 and ROS 1 Melodic."
    fi
    ROS_DISTRO_TO_INSTALL="melodic"
  elif [ $UBUNTU_VERSION == "20.04" ]; then
    ROS_DISTRO_TO_INSTALL="noetic"
  else
    echo -e "${BOLD}${RED}Unsupported Ubuntu verison: $UBUNTU_VERSION.${NORM}${OFF}"
    failed "Interbotix LoCoBot only works with Ubuntu 18.04 bionic or 20.04 focal on your hardware."
  fi
fi

validate_distro
check_ubuntu_version

if [ "$NONINTERACTIVE" = false ]; then
  echo -e "${BLU}${BOLD}INSTALLATION SUMMARY:"
  echo -e "\tROS Distribution:           ROS ${ROS_VERSION_TO_INSTALL} ${ROS_DISTRO_TO_INSTALL}"
  echo -e "\tBase Type:                  ${BASE_TYPE}"
  echo -e "\tInstallation path:          ${INSTALL_PATH}"
  echo -e "\nIs this correct?\n${PROMPT}${NORM}${OFF}\c"
  read -r resp

  if [[ $resp == [yY] || $resp == [yY][eE][sS] ]]; then
    :
  else
    help && exit 0
  fi
fi

echo -e "\n\n"
echo -e "${GRN}${BOLD}**********************************************${NORM}${OFF}"
echo ""
echo -e "${GRN}${BOLD}            Starting installation!            ${NORM}${OFF}"
echo -e "${GRN}${BOLD}   This process may take around 30 Minutes!   ${NORM}${OFF}"
echo ""
echo -e "${GRN}${BOLD}      Be ready reenter password if needed.    ${NORM}${OFF}"
echo ""
echo -e "${GRN}${BOLD}**********************************************${NORM}${OFF}"
echo -e "\n\n"

sleep 4
start_time="$(date -u +%s)"

echo -e "\n# Interbotix Configurations" >> ~/.bashrc

export INTERBOTIX_XSLOCOBOT_BASE_TYPE=${BASE_TYPE}

# Configure Ubuntu repositories to allow restricted, universe, and multiverse
sudo add-apt-repository universe
sudo add-apt-repository multiverse
sudo add-apt-repository restricted

# Update the system
sudo apt update && sudo apt -y upgrade
sudo apt -y autoremove

install_essential_packages

# configure LoCoBot computer ethernet to use proper network config for Create 3
if [[ $BASE_TYPE == 'create3' ]]; then
  sudo apt -y install netplan.io
  export CREATE3_NETWORK_CONFIG="network:
  version: 2
  ethernets:
    eno1:
      dhcp4: false
      optional: true
      addresses: [192.168.186.3/24]
"
  if [ ! -f "/etc/netplan/99_config.yaml" ]; then
    if [ ! -d "/etc/netplan/" ]; then
      sudo mkdir -p /etc/netplan/
    fi
    sudo touch /etc/netplan/99_config.yaml
    sudo bash -c 'echo -e "'"$CREATE3_NETWORK_CONFIG"'" > /etc/netplan/99_config.yaml'
    sudo netplan apply
    sleep 10
  fi
fi

mkdir -p $INSTALL_PATH/src

shopt -s extglob

if [[ $ROS_VERSION_TO_INSTALL == 1 ]]; then
  install_ros1
  if [[ $BASE_TYPE == 'kobuki' ]]; then
    install_kobuki_ros1
  elif [[ $BASE_TYPE == 'create3' ]]; then
    install_create3_ros1
  fi
  install_locobot_ros1
elif [[ $ROS_VERSION_TO_INSTALL == 2 ]]; then
  failed "ROS 2 is not yet supported on the LoCoBot platform."
  install_ros2
  install_perception_ros2
  if [[ $BASE_TYPE == 'kobuki' ]]; then
    install_kobuki_ros2
  elif [[ $BASE_TYPE == 'create3' ]]; then
    install_create3_ros2
  fi
  install_locobot_ros2
else
  failed "Something went wrong."
fi

shopt -u extglob

setup_env_vars

end_time="$(date -u +%s)"
elapsed="$(($end_time-$start_time))"

echo -e "${GRN}Installation complete, took $elapsed seconds in total.${OFF}"
echo -e "${GRN}NOTE: Remember to reboot the computer before using the robot!${OFF}"
