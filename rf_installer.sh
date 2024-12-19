#
# Copyright 2024 RapidFort Inc. All Rights Reserved.
#
#
#  RAPIDFORT_ROOT_DIR           absolute installation path for entrypoints
#  RAPIDFORT_BIN_DIR            absolute installation path for binaries
#  EXISTING_INSTALL_VERSION     optional if installed
#  NEW_INSTALL_VERSION          new installer version
#  USER_HOME                    instal user home directory
#
if [ -n "${RF_APP_HOST}" ]; then
    export RF_APP_HOST="${RF_APP_HOST}"
else
    export RF_APP_HOST=us01.rapidfort.com
fi

USER_HOME=${HOME}
CLI_PYTHON=
RAPIDFORT_ROOT_DIR=
RAPIDFORT_BIN_DIR=
IS_INSTALL_LOCATION_IN_PATH=
LOCAL_INSTALLER_FILE=
INSTALLER_FILE=
INSTALLER_VERSION=

get_os_str()
{
    # works on all posix shell
    _os="$(uname | tr '[:upper:]' '[:lower:]')"
    echo "${_os}"
}

get_architecture()
{
    _arch="$(uname -m)"
    if [ "${_arch}" = "aarch64" ] || [ "${_arch}" = "arm64" ]; then
        echo "arm64"
    elif [ "${_arch}" = "amd64" ] || [ "${_arch}" = "x86_64" ]; then
        echo "amd64"
    else
        echo "ERROR: $(get_os_str): ${_arch} not supported."
        exit 1
    fi
}

have_tty()
{
    # return success if both stdin and stdout are tty
    if [ ! -p /dev/stdin ] && [ -t 0 ] && [ -t 1 ] ; then
        return 0
    fi
    return 1
}

# some colors
if have_tty ; then
    __red='\033[0;31m'
    __yellow='\033[0;33m'
    __green='\033[0;32m'
    __bold='\033[1m'
    __color_off='\033[0m'
else
    __red=""
    __yellow=""
    __green=""
    __bold=""
    __color_off=""
fi

ECHO_EVAL=
echo -e rf | grep -q '-e rf'
err=$?
if [ $err -eq 1 ]; then
    ECHO_EVAL=-e
fi

now()
{
    date +"%F %T"
}

log_error()
{
    echo $ECHO_EVAL "${__red}$(now): ${*}${__color_off}"
}

log_warn()
{
    echo $ECHO_EVAL "${__yellow}$(now): ${*}${__color_off}"
}

log_info()
{
   echo $ECHO_EVAL "${__green}$(now): ${*}${__color_off}"
}

remove_entrypoints()
{
    src="${1}"
    rm -f "${src}"/rfcat
    rm -f "${src}"/rfconfigure
    rm -f "${src}"/rfharden
    rm -f "${src}"/rfinfo
    rm -f "${src}"/rfjobs
    rm -f "${src}"/rflens
    rm -f "${src}"/rflogin
    rm -f "${src}"/rfls
    rm -f "${src}"/rfrbom
    rm -f "${src}"/rfsbom
    rm -f "${src}"/rfscan
    rm -f "${src}"/rfstub
}

add_entrypoint()
{
    install_path="${1}"
    entrypoint="${2}"

    cat<<'EOF_CMD' > "${install_path}"/"${entrypoint}"
#!/bin/sh
#
# Copyright 2024 RapidFort Inc. All Rights Reserved.
#

if [ ! -p /dev/stdin ] && [ -t 0 ] && [ -t 1 ] ; then
    tty=" -it"
else
    tty=""
fi

RF_CONTAINER_ENGINE=docker
${RF_CONTAINER_ENGINE} run \
    --rm $tty \
    -e RF_CLI_COPY_MODE=1 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v ${HOME}/.rapidfort:/root/.rapidfort \
    quay.io/rapidfort/rfcli "$(basename ${0})" "${@}"
EOF_CMD

    chmod +x "${install_path}"/"${entrypoint}"
}

create_entrypoints_symlinks()
{
    src="${1}"
    target="${2}"
    ln -sf "${src}"/rfcat       "${target}"/rfcat
    ln -sf "${src}"/rfconfigure "${target}"/rfconfigure
    ln -sf "${src}"/rfharden    "${target}"/rfharden
    ln -sf "${src}"/rfinfo      "${target}"/rfinfo
    ln -sf "${src}"/rfjobs      "${target}"/rfjobs
    ln -sf "${src}"/rflens      "${target}"/rflens
    ln -sf "${src}"/rflogin     "${target}"/rflogin
    ln -sf "${src}"/rfls        "${target}"/rfls
    ln -sf "${src}"/rfrbom      "${target}"/rfrbom
    ln -sf "${src}"/rfsbom      "${target}"/rfsbom
    ln -sf "${src}"/rfscan      "${target}"/rfscan
    ln -sf "${src}"/rfstub      "${target}"/rfstub
}

rapidfort_which()
{
    command_path=$(command -v "${1}")
    if [ -n "${command_path}" ]; then
        echo "${command_path}"
    else
        echo ""
    fi
}

check_directory_in_path()
{
    target_dir="${1}"
    path_dirs=$(echo "$PATH" | tr ':' '\n')

    for dir in $path_dirs; do
        if [ "$dir" = "$target_dir" ] ; then
            echo 0
            return
        fi
    done
    echo 1
}

rapidfort_root_dir()
{

# The function essentially resolves the given path to its root directory,
# handling absolute and relative paths, symbolic links, and ensuring the path is in its simplest form.

  case $1 in
  /*)   _rapidfort_path=$1
        ;;
  */*)  _rapidfort_path=$PWD/$1
        ;;
  *)    _rapidfort_path=$(rapidfort_which "$1")
        case $_rapidfort_path in
        /*) ;;
        *)  _rapidfort_path=$PWD/$_rapidfort_path ;;
        esac
        ;;
  esac
  _rapidfort_dir=0
  while :
  do
    while _rapidfort_link=$(readlink "$_rapidfort_path")
    do
      case $_rapidfort_link in
      /*) _rapidfort_path=$_rapidfort_link ;;
      *)  _rapidfort_path=$(dirname "$_rapidfort_path")/$_rapidfort_link ;;
      esac
    done
    case $_rapidfort_dir in
    1)  break ;;
    esac
    if [ -d "${_rapidfort_path}" ]; then
      break
    fi
    _rapidfort_dir=1
    _rapidfort_path=$(dirname "$_rapidfort_path")
  done
  while :
  do  case $_rapidfort_path in
      */)     _rapidfort_path=$(dirname "$_rapidfort_path/.")
              ;;
      */.)    _rapidfort_path=$(dirname "$_rapidfort_path")
              ;;
      *)      echo "$_rapidfort_path"
              break
              ;;
      esac
  done
}

order_python_no_check()
{
    selected_version=""
    for python_version in "$@"
    do
        if [ -z "$selected_version" ]; then
            if rapidfort_which "$python_version" > /dev/null; then
                selected_version=$python_version
            fi
        fi
    done
    if [ -z "$selected_version" ]; then
        selected_version=python
    fi
    echo "$selected_version"
}

order_python()
{
    selected_version=""
    for python_version in "$@"
        do
            if [ -z "$selected_version" ]; then
                if "$python_version" -c "import sys; sys.exit(0 if ((3,8) <= (sys.version_info.major, sys.version_info.minor) <= (3,14)) else 1)" > /dev/null 2>&1; then
                    selected_version=$python_version
                fi
            fi
        done
    echo "$selected_version"
}

setup_rapidfort_python()
{
    CLI_PYTHON=$(order_python python3 python python3.14 python3.13 python3.12 python3.11 python3.10 python3.9 python3.8)
    if [ -z "$CLI_PYTHON" ]; then
      CLI_PYTHON=$(order_python_no_check python3 python)
    fi
    if [ -z "${CLI_PYTHON}" ]; then
        log_error "ERROR: To use the RapidFort CLI, you must have Python installed and on your PATH."
        exit 1
    fi
}

check_tools()
{
    if [ "$(get_os_str)" = "darwin" ]; then

        container_engine="docker"
        if [ ! -x "$(rapidfort_which "$container_engine")" ]; then
            log_error "ERROR: you must have docker installed and in your PATH."
            exit 1
        fi

        $container_engine version >/dev/null 2>&1
        err=$?
        if [ $err != 0 ];  then
            log_error "ERROR: ${container_engine} must be running before installing cli"
            exit 1
        fi

    else
        container_engines="docker podman"
        _needed_tools="curl tar sed chown getent stat mkdir rm id ln tr"
        _have_all_tools=1
        for tool in $_needed_tools ; do
            if [ ! -x "$(rapidfort_which "$tool")" ]; then
                log_error "ERROR: $tool command not accessible."
                _have_all_tools=0
            fi
        done

        if [ "$_have_all_tools" = 0 ] ; then
            log_error "ERROR: To install the RapidFort CLI, you must have the following installed and in your PATH."
            log_error "       $_needed_tools"
            exit 1
        fi

        for engine in $container_engines; do
            if [ -x "$(rapidfort_which "$engine")" ]; then
                CONTAINER_ENGINE="$engine"
                break
            fi
        done

        if [ -z "${CONTAINER_ENGINE}" ]; then
            log_warn "WARNING: Docker or Podman not found."
            log_warn "WARNING: Container image scanning will not function without Docker or Podman installed and in your PATH."
        fi
        setup_rapidfort_python
    fi
}

patch_elf_file()
{
    patchelf_dir="$1"
    interp_path="$2"
    elf_file="$3"
    lock_dir="${elf_file}".rfp    # create this dir so scripts know it's already patched

    if [ ! -s "$elf_file" ] ; then
        log_error "ERROR: '$elf_file' is not accessible for patching." >&2
        exit 1
    fi

    mkdir -p "$lock_dir" 2>/dev/null
    err="$?"

    if [ "$err" = 0 ] ; then           # not patched yet. proceed
        "${patchelf_dir}"/patchelf --set-interpreter "${interp_path}" "${elf_file}"
        err="$?"
        if [ "$err" != 0 ] ; then
            log_error "ERROR: Cannot patch $elf_file."
            exit 1
        fi
        echo "0" > "${lock_dir}"/ret
        echo "$interp_path" > "${lock_dir}"/interp
    else
        log_error "ERROR: Could not install and update $elf_file."
        exit 1
    fi
    return 0
}

patch_bins()
{
    tools_dir="$1"
    root_dir="$2"

    install_dir="/.rapidfort_RtmF/tmp/tools"
    if [ "$(get_architecture)" = "arm64" ]; then
        patch_elf_file "${tools_dir}" "${install_dir}"/rpmbins/ld-linux-aarch64.so.1 "${tools_dir}"/rpmbins/rpm
        patch_elf_file "${tools_dir}" "${install_dir}"/rpmbins/ld-linux-aarch64.so.1 "${tools_dir}"/rpmbins/rpmdb
        patch_elf_file "${tools_dir}" "${root_dir}"/tools/lib/ld-musl-aarch64.so.1 "${tools_dir}"/rf_make_dockerfiles
    else
        patch_elf_file "${tools_dir}" "${install_dir}"/rpmbins/ld-linux-x86-64.so.2 "${tools_dir}"/rpmbins/rpm
        patch_elf_file "${tools_dir}" "${install_dir}"/rpmbins/ld-linux-x86-64.so.2 "${tools_dir}"/rpmbins/rpmdb
        patch_elf_file "${tools_dir}" "${root_dir}"/tools/lib/ld-musl-x86_64.so.1 "${tools_dir}"/rf_make_dockerfiles
    fi
    sed -i "s|#!/bin/bash|#!${tools_dir}/bash|" "${tools_dir}"/../lib/rapidfort/rfcat/rfcat.sh
}

curl_status_check()
{
    curl_status="${1}"
    curl_output="${2}"

    if [ "$curl_status" -ne 0 ]; then
        case $1 in
            6)
                log_error "ERROR: curl failed to resolve host: ${RF_APP_HOST}"
                exit "$curl_status"
                ;;
            28)
                log_error "ERROR: curl timed out for host: ${RF_APP_HOST}"
                exit "$curl_status"
                ;;
            *)
                log_error "ERROR: curl command encountered an error with exit code $1 for host: ${RF_APP_HOST}"
                log_error "$curl_output"
                exit "$curl_status"
                ;;
        esac
    fi
}

check_curl_progress_bar()
{
    # curl 7.71.1 and later versions support progress-bar
    curl_version=$(curl --version | awk 'NR==1{print $2}')

    major=$(echo "$curl_version" | cut -d. -f1)
    minor=$(echo "$curl_version" | cut -d. -f2)
    patch=$(echo "$curl_version" | cut -d. -f3)

    if [ "$major" -gt 7 ] ; then
        return 0
    elif [ "$major" -eq 7 ] && [ "$minor" -gt 70 ] ; then
        return 0
    elif [ "$major" -eq 7 ] && [ "$minor" -eq 71 ] && [ "$patch" -gt 0 ] ; then
        return 0
    else
        return 1
    fi
}

uninstall()
{
    if [ -d "${USER_HOME}"/.rapidfort ]; then
        rm -rf "${USER_HOME}"/.rapidfort
    fi

    if [ "$(get_os_str)" = "darwin" ]; then
        docker rmi quay.io/rapidfort/rfcli
    fi

    EXISTING_INSTALL_PATH=$(rapidfort_which rflogin)
    if [ -n "${EXISTING_INSTALL_PATH}" ] ; then
        RAPIDFORT_ROOT_DIR=$(rapidfort_root_dir "${EXISTING_INSTALL_PATH}")

        remove_entrypoints "${RAPIDFORT_ROOT_DIR}/.."
        remove_entrypoints "${RAPIDFORT_ROOT_DIR}"

        if [ -d "${RAPIDFORT_ROOT_DIR}" ]; then
            rm -r "${RAPIDFORT_ROOT_DIR}"
            err=$?
            if [ $err -ne 0 ]; then
                exit 0
            fi
        fi
    else
        log_info "RapidFort CLI not found"
        exit 0
    fi
    log_info "Successfully uninstalled RapidFort CLI."
    exit 0
}

downlaod_bundle()
{
    INSTALLER_VERSION=$(curl -k -s --connect-timeout 10 https://"${RF_APP_HOST}"/cli/VERSION)
    err=$?
    curl_status_check $err

    if [ -z "${INSTALLER_VERSION}" ]; then
        log_error "ERROR: Failed to get the RapidFort CLI version from the server. Exiting..."
        exit 1
    fi

    CLI_URL="https://$RF_APP_HOST/cli/$(get_architecture)/rapidfort_cli-${INSTALLER_VERSION}.tar.gz"
    log_info "${__bold}Downloading CLI bundle from ${CLI_URL}"
    if check_curl_progress_bar ; then
        output=$(curl -k --connect-timeout 10 --progress-meter "${CLI_URL}" -o "rapidfort_cli-${INSTALLER_VERSION}.tar.gz")
        err=$?
        curl_status_check $err "$output"
    else
        output=$(curl -k -s --connect-timeout 10 "${CLI_URL}" -o "rapidfort_cli-${INSTALLER_VERSION}.tar.gz")
        err=$?
        curl_status_check $err "$output"
    fi

    INSTALLER_FILE="rapidfort_cli-${INSTALLER_VERSION}.tar.gz"
}

print_usage()
{
    echo "  -h, --help"
    echo "  -d, --download-only         Download cli bundle but dont install"
    echo "  -f, --file <cli_bundle>     Install from local file"
    echo "  -p, --install-path <path>   RapidFort CLI install location"
    echo "  -u, --uninstall             Uninstall RapidFort CLI"
    exit 0
}

# Parse command line arguments
for arg in "$@"; do
  shift
  case "$arg" in
    '--help')           set -- "$@" '-h'   ;;
    '--download-only')  set -- "$@" '-d'   ;;
    '--file')           set -- "$@" '-f'   ;;
    '--install-path')   set -- "$@" '-p'   ;;
    '--uninstall')      set -- "$@" '-u'   ;;
    *)                  set -- "$@" "$arg" ;;
  esac
done

# Set install path
# 1st precedence: Custom location for installation
OPTIND=1
while getopts "p:f:hud" opt; do
  case "$opt" in
    'h') print_usage ;;
    'f')
        if [ -z "${OPTARG}" ]; then
            print_usage
        fi
        LOCAL_INSTALLER_FILE="${OPTARG}"
        ;;
    'p')
        if [ -z "${OPTARG}" ]; then
            print_usage
        fi
        RAPIDFORT_ROOT_DIR="${OPTARG}"
        # POSIX compatible absolute path check
        case "${RAPIDFORT_ROOT_DIR}" in
            /*)
                : # do nothing
                ;;
            *)
                log_error "ERROR: Installation path must be an absolute path. given: ${RAPIDFORT_ROOT_DIR}"
                exit 1
                ;;
        esac
        ;;
    'd') downlaod_bundle >&2
         exit 0 ;;
    '?') print_usage >&2; ;;
    'u') uninstall ;;
  esac
done
shift $((OPTIND - 1))

log_info "Welcome to the RapidFort CLI installation!"
check_tools

# If installing as root user
if [ "$(id -u)" = 0 ]; then
    # Setup USER_HOME for initial configuration
    if [ -n "${SUDO_USER}" ]; then
        USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d ':' -f6)
    else
        USER_HOME=${HOME}
    fi
else
    USER_HOME=${HOME}
fi

if [ -z "${RAPIDFORT_ROOT_DIR}" ] ; then

    RFLOGIN_PATH=$(rapidfort_which rflogin)
    if [ -n "${RFLOGIN_PATH}" ]; then
        EXISTING_INSTALL_PATH=$(dirname $(rapidfort_which rflogin))
    fi

    if [ -f "${EXISTING_INSTALL_PATH}" ]; then
        # 2nd precedence: Install same place as existing install
        log_info "Your current RapidFort CLI location is: ${__bold}$(rapidfort_root_dir "${EXISTING_INSTALL_PATH}")"
        log_info "Your current RapidFort CLI version is: ${__bold}$("${EXISTING_INSTALL_PATH}" --version)"

        RAPIDFORT_ROOT_DIR=$(rapidfort_root_dir "${EXISTING_INSTALL_PATH}")

    elif [ "$(id -u)" = 0 ]; then
        # 3rd precedence:
        RAPIDFORT_ROOT_DIR=/usr/local/bin

    else
        # 4th precedence: install location is same location wherever installer is executed
        RAPIDFORT_ROOT_DIR=$(pwd)

    fi
fi

export RAPIDFORT_ROOT_DIR

if [ ! -d "${RAPIDFORT_ROOT_DIR}" ]; then
    mkdir -p "${RAPIDFORT_ROOT_DIR}"
fi

IS_INSTALL_LOCATION_IN_PATH=$(check_directory_in_path "${RAPIDFORT_ROOT_DIR}")
if [ "$IS_INSTALL_LOCATION_IN_PATH" -eq 0 ]; then
    RAPIDFORT_BIN_DIR="${RAPIDFORT_ROOT_DIR}"/rapidfort
    mkdir -p "${RAPIDFORT_BIN_DIR}"
fi

if [ -n "${LOCAL_INSTALLER_FILE}" ]; then
    if [ ! -f "${LOCAL_INSTALLER_FILE}" ]; then
         log_error "ERROR: ${LOCAL_INSTALLER_FILE} not found"
         exit 1
    fi
else
    INSTALLER_VERSION=$(curl -k -s --connect-timeout 10 https://"${RF_APP_HOST}"/cli/VERSION)
    err=$?
    curl_status_check $err

    if [ -z "${INSTALLER_VERSION}" ]; then
        log_error "ERROR: Failed to get the RapidFort CLI version from the server. Exiting..."
        exit 1
    fi
    log_info New RapidFort CLI version is: "${__bold}${INSTALLER_VERSION}"
    log_info "RapidFort CLI installation path is: ${__bold}${RAPIDFORT_ROOT_DIR}"

    if [ "$(get_os_str)" = "darwin" ]; then
        log_info "${__bold}Pulling the RapidFort CLI image: quay.io/rapidfort/rfcli"
        docker pull quay.io/rapidfort/rfcli:latest 2>&1 | grep -vE "docker scout quickview|What's Next?"
        err=$?
        if [ $err != 0 ]; then
            log_error "ERROR: Failed to pull quay.io/rapidfort/rfcli image"
            exit 1
        fi
    else
        downlaod_bundle
    fi
fi

log_info "${__bold}Installing CLI bundle..."

if [ "$(get_os_str)" != "darwin" ]; then
    if [ -n "${RAPIDFORT_BIN_DIR}" ]; then
        rm -rf "${RAPIDFORT_BIN_DIR}"/tools/rf_make_dockerfiles.rfp
        if [ -n "${LOCAL_INSTALLER_FILE}" ]; then
            tar -xzpf "${LOCAL_INSTALLER_FILE}" -C "${RAPIDFORT_BIN_DIR}"
        else
            tar -xzpf "${INSTALLER_FILE}" -C "${RAPIDFORT_BIN_DIR}"
        fi
        patch_bins "${RAPIDFORT_BIN_DIR}"/tools "${RAPIDFORT_BIN_DIR}"

        remove_entrypoints "${RAPIDFORT_ROOT_DIR}"
        create_entrypoints_symlinks "${RAPIDFORT_BIN_DIR}" "${RAPIDFORT_ROOT_DIR}"

    else
        rm -rf "${RAPIDFORT_ROOT_DIR}"/tools/rf_make_dockerfiles.rfp
        if [ -n "${LOCAL_INSTALLER_FILE}" ]; then
            tar -xzpf "${LOCAL_INSTALLER_FILE}" -C "${RAPIDFORT_ROOT_DIR}"
        else
            tar -xzpf "${INSTALLER_FILE}" -C "${RAPIDFORT_ROOT_DIR}"
        fi
        patch_bins "${RAPIDFORT_ROOT_DIR}"/tools "${RAPIDFORT_ROOT_DIR}"
    fi

    if [ -z "${LOCAL_INSTALLER_FILE}" ]; then
        rm "${INSTALLER_FILE}"
    fi

else
    install_path="${RAPIDFORT_ROOT_DIR}"
    if [ -n "${RAPIDFORT_BIN_DIR}" ]; then
        install_path="${RAPIDFORT_BIN_DIR}"
    fi

    add_entrypoint "${install_path}" "rfcat"
    add_entrypoint "${install_path}" "rfconfigure"
    add_entrypoint "${install_path}" "rfharden"
    add_entrypoint "${install_path}" "rfinfo"
    add_entrypoint "${install_path}" "rfjobs"
    add_entrypoint "${install_path}" "rflens"
    add_entrypoint "${install_path}" "rflogin"
    add_entrypoint "${install_path}" "rfls"
    add_entrypoint "${install_path}" "rfrbom"
    add_entrypoint "${install_path}" "rfsbom"
    add_entrypoint "${install_path}" "rfscan"
    add_entrypoint "${install_path}" "rfstub"

    if [ -n "${RAPIDFORT_BIN_DIR}" ]; then
        remove_entrypoints "${RAPIDFORT_ROOT_DIR}"
        create_entrypoints_symlinks "${RAPIDFORT_BIN_DIR}" "${RAPIDFORT_ROOT_DIR}"
    fi
fi

log_info "Setting up RapidFort platform to https://${RF_APP_HOST}"
if [ -n "$RF_APP_HOST" ]; then
    mkdir -p "${USER_HOME}"/.rapidfort
    if [ -f "${USER_HOME}"/.rapidfort/credentials ] ; then
        sed -i.bak "s/api_root_url.*=*$/rf_root_url=https:\/\/${RF_APP_HOST}/" "${USER_HOME}"/.rapidfort/credentials
        sed -i.bak "s/rf_root_url.*=*$/rf_root_url=https:\/\/${RF_APP_HOST}/" "${USER_HOME}"/.rapidfort/credentials
    else
        echo "[rapidfort-user]" > "${USER_HOME}"/.rapidfort/credentials
        echo "rf_root_url = https://${RF_APP_HOST}" >> "${USER_HOME}"/.rapidfort/credentials
    fi

    if [ -n "${SUDO_USER}" ]; then
        chown -R "${SUDO_USER}" "${USER_HOME}"/.rapidfort
    fi
fi

log_info "Successfully installed RapidFort CLI!"

if [ "$IS_INSTALL_LOCATION_IN_PATH" -ne 0 ]; then
    log_info "Add ${__bold}--> ${RAPIDFORT_ROOT_DIR} <-- to your PATH to use the RapidFort CLI tools."
fi


