#!/bin/bash

set -e

THIS_DIR=$(readlink -f "${BASH_SOURCE[0]}")
THIS_DIR=$(dirname "${THIS_DIR}")

trap _exec_exit_hook EXIT
function _exec_exit_hook() {
    local _idx
    for ((_idx = ${#_EXIT_HOOKS[@]} - 1; _idx >= 0; _idx--)); do
        eval "${_EXIT_HOOKS[_idx]}" || true
    done
}

function _add_exit_hook() {
    while (($#)); do
        _EXIT_HOOKS+=("$1")
        shift
    done
}

PACKAGES=${PACKAGES:-""}

function _add_package() {
    local _before=0
    if [[ ${1} == "-b" ]]; then
        _before=1
        shift
    fi
    while (($#)); do
        if [[ ${PACKAGES} != *"${1}"* ]]; then
            if [[ ${_before} -gt 0 ]]; then
                PACKAGES="${1}${PACKAGES:+ ${PACKAGES}}"
            else
                PACKAGES="${PACKAGES:+${PACKAGES} }${1}"
            fi
        fi
        shift
    done
}

_add_package -b wpad dnsmasq-full
_add_package -b "-wpad-mini" "-wpad-basic" "-dnsmasq"
_add_package luci luci-theme-bootstrap
# kmod-dax kmod-dm is required for ventoy
_add_package kmod-dax kmod-dm

function _check_param() {
    while (($#)); do
        if [[ -z ${!1} ]]; then
            echo "\${$1} is required"
            return 1
        fi
        shift 1
    done
}

function print_usage() {
    #shellcheck disable=SC2016
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS]
OPTIONS
    -h, show help.
    -b BINDIR, the output directory for image. ${BINDIR:+The default is '"${BINDIR}"'}
    -c, clean build. ${CLEAN:+The default is "${CLEAN}"}
    -d, dry run. ${DRYRUN:+The default is '"${DRYRUN}"'}
    -k KUSTOMIZE, the directory for customized files, refer to https://openwrt.org/docs/guide-developer/uci-defaults. ${KUSTOMIZE:+The default is "${KUSTOMIZE}"}
    -n, the customize name. ${NAME:+The default is '"${NAME}"'}
    -p PACKAGES, additional packages. ${PACKAGES:+The default is '"${PACKAGES}"'}
    -t THIRDPARTY, Thirdparty package directory. ${THIRDPARTY:+The default is '"${THIRDPARTY}"'}
    -v VERSION, the OpenWRT version. ${VERSION:+The default is '"${VERSION}"'}
EOF
}

BINDIR=${BINDIR:-""}
CLEAN=0
DRYRUN=0
KUSTOMIZE=${KUSTOMIZE:-"${THIS_DIR}/config"}
NAME=${NAME:-default}
THIRDPARTY=${THIRDPARTY:-""}
VERSION=${VERSION:-"22.03.0"}

while getopts "hb:cdk:n:p:t:v:" OPTION; do
    case $OPTION in
    h)
        print_usage
        exit 0
        ;;
    c)
        CLEAN=1
        ;;
    d)
        DRYRUN=1
        ;;
    b)
        BINDIR=$(readlink -f "${OPTARG}")
        ;;
    k)
        KUSTOMIZE=$(readlink -f "${OPTARG}")
        ;;
    n)
        NAME=${OPTARG}
        ;;
    p)
        PACKAGES="${PACKAGES:+$PACKAGES }${OPTARG}"
        ;;
    t)
        THIRDPARTY=$(readlink -f "${OPTARG}")
        ;;
    v)
        VERSION=${OPTARG}
        ;;
    *)
        print_usage
        exit 1
        ;;
    esac
done

_check_param VERSION
if [[ -z ${BINDIR} ]]; then
    BINDIR=${THIS_DIR}/${VERSION}-bin
fi

if [[ ${CLEAN} -gt 0 && -d "${BINDIR}" ]]; then
    rm -fr "${BINDIR}"
fi
if [[ ! -d ${BINDIR} ]]; then
    mkdir -p "${BINDIR}"
fi

docker_image_name=docker.io/openwrtorg/imagebuilder:x86-64-${VERSION}
docker image pull "${docker_image_name}"

docker_opts=(--rm -it -u "$(id -u):$(id -g)" -v "${BINDIR}":/home/build/openwrt/bin)
makecmd="make image"
if [[ $(timedatectl show | grep Timezone | cut -d= -f2) == Asia/Shanghai ]]; then
    OPENWRT_MIRROR_PATH=${OPENWRT_MIRROR_PATH:-http://mirrors.ustc.edu.cn/openwrt}
    cmd=${cmd:+${cmd}; }"sed -i -e 's|http://downloads.openwrt.org|${OPENWRT_MIRROR_PATH}|g' -e 's|https://downloads.openwrt.org|${OPENWRT_MIRROR_PATH}|g' repositories.conf"
fi
for item in http_proxy https_proxy no_proxy; do
    if [[ -n ${!item} ]]; then
        docker_opts+=(--env "${item}=${!item}")
    fi
done
if [[ -n ${THIRDPARTY} ]]; then
    docker_opts+=(-v "${THIRDPARTY}:/home/build/openwrt/thirdparty")
    cmd="${cmd:+${cmd}; }sed -i -e '\|^## Place your custom repositories here.*|a src custom file:///home/build/openwrt/thirdparty' -e 's/^option check_signature$/# &/' repositories.conf"
fi

if [[ -n ${KUSTOMIZE} ]]; then
    docker_opts+=(-v "${KUSTOMIZE}:/home/build/openwrt/custom")
    _cmd="${_cmd} FILES=/home/build/customize"
    #shellcheck disable=SC2086
    docker_cmd=${docker_cmd:+${docker_cmd} }"-v $(readlink -f ${KUSTOMIZE}):/home/build/customize"
    if [[ -n ${OPENWRT_MIRROR_PATH} ]]; then
        mkdir -p "${KUSTOMIZE}/etc/uci-defaults"
        cat <<EOF > "${KUSTOMIZE}/etc/uci-defaults/10_opkg"
#!/bin/sh

sed -i -e 's|https://downloads.openwrt.org|${OPENWRT_MIRROR_PATH}|g' -e 's|http://downloads.openwrt.org|${OPENWRT_MIRROR_PATH}|g' /etc/opkg/distfeeds.conf
# sed -i -e 's|${OPENWRT_MIRROR_PATH}|http://downloads.openwrt.org|g' /etc/opkg/distfeeds.conf

exit 0
EOF
    fi

    makecmd="${makecmd} FILES=/home/build/openwrt/custom"
    _add_exit_hook "rm -f ${KUSTOMIZE}/etc/uci-defaults/10_opkg"
fi

if [[ -n ${NAME} ]]; then
    makecmd="${makecmd} EXTRA_IMAGE_NAME=${NAME}"
fi
if [[ -n ${PACKAGES} ]]; then
    makecmd="${makecmd} PACKAGES=\"${PACKAGES}\""
fi

if [[ ${DRYRUN} -eq 0 ]]; then
    docker run "${docker_opts[@]}" "${docker_image_name}" bash -c "${cmd}; ${makecmd}"
else
    echo "${makecmd}"
    docker run "${docker_opts[@]}" "${docker_image_name}" bash -c "${cmd}; bash"
fi

if [[ $(command -v qemu-img) && ${DRYRUN} -eq 0 ]]; then
    while IFS= read -r _gz_image; do
        _prefix=$(dirname "${_gz_image}")
        _img=${_prefix}/$(basename -s .gz "${_gz_image}")
        _qcow=${_prefix}/$(basename -s .img.gz "${_gz_image}").qcow2c
        if [[ -f "${_qcow}" ]]; then
            continue
        fi
        if [[ ! -f "${_img}" ]]; then
            gunzip -k "${_gz_image}" || true
        fi
        qemu-img convert -c -O qcow2 "${_img}" "${_qcow}"
        qemu-img convert -O qcow2 "${_qcow}" "${_img}" # Ventoy use img
        unset -v _prefix _img _qcow
    done < <(find "${BINDIR}/targets/x86/64" -iname "*-combined*.img.gz" | grep -v efi | sort)
fi
