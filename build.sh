#!/bin/bash

set -e

function print_usage() {
    #shellcheck disable=SC2016
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS]
OPTIONS
    -h, show help.
    -a PACKAGES, additional packages. ${PACKAGES:+The default is "${PACKAGES}"}
    -b BINDING, the bin directory binding for image output. ${BINDING:+The default is '"${BINDING}"'}
    -c, clean build. ${CLEAN:+The default is "${CLEAN}"}
    -k KUSTOMIZE, the directory for customized files, refer to https://openwrt.org/docs/guide-developer/uci-defaults. ${KUSTOMIZE:+The default is "${KUSTOMIZE}"}
    -n, the customize name. ${NAME:+The default is '"${NAME}"'}
    -v VERSION, the openwrt version. ${VERSION:+The default is '"${VERSION}"'}
EOF
}

BINDING=${BINDING:-"$PWD/bin"}
CLEAN=0
DOCKER_IMAGE=docker.io/openwrtorg/imagebuilder:x86-64
KUSTOMIZE=${KUSTOMIZE:-""}
NAME=${NAME:-default}
PACKAGES=${PACKAGES:+${PACKAGES} }"kmod-dax kmod-dm" # kmod-dax kmod-dm is required for ventoy
VERSION=${VERSION:-"21.02.2"}

_cmd=""
if [[ $(timedatectl show | grep Timezone | cut -d= -f2) == Asia/Shanghai ]]; then
    OPENWRT_MIRROR_PATH=${OPENWRT_MIRROR_PATH:-http://mirrors.ustc.edu.cn/openwrt}
    _cmd=${_cmd:+${_cmd}; }"sed -i -e \"s|http://downloads.openwrt.org|${OPENWRT_MIRROR_PATH}|g\" -e \"s|https://downloads.openwrt.org|${OPENWRT_MIRROR_PATH}|g\" repositories.conf"
fi

while getopts "ha:b:ck:n:v:" OPTION; do
    case $OPTION in
    h)
        print_usage
        exit 0
        ;;
    c)
        CLEAN=1
        ;;
    a)
        PACKAGES="${PACKAGES:+$PACKAGES }${OPTARG}"
        ;;
    b)
        BINDING=${OPTARG}
        ;;
    k)
        KUSTOMIZE=${OPTARG}
        ;;
    n)
        NAME=${OPTARG}
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

if [[ ${CLEAN} -gt 0 && -d "${BINDING}" ]]; then
    rm -fr "${BINDING}"
fi
if [[ ! -d ${BINDING} ]]; then
    mkdir -p "${BINDING}"
fi

docker_cmd="docker run --rm -t"
#shellcheck disable=SC2086
docker_cmd=${docker_cmd:+${docker_cmd} }"-u build:$(id -gn) --group-add $(id -gn) -v $(readlink -f ${BINDING}):/home/build/openwrt/bin"
for item in http_proxy https_proxy no_proxy; do
    if [[ -n ${!item} ]]; then
        docker_cmd=${docker_cmd:+${docker_cmd} }"--env ${item}=${!item} --env ${item^^}=${!item}"
    fi
done

_cmd=${_cmd:+${_cmd}; }"make image EXTRA_IMAGE_NAME=${NAME}"
if [[ -n ${KUSTOMIZE} ]]; then
    _cmd="${_cmd} FILES=/home/build/customize"
    #shellcheck disable=SC2086
    docker_cmd=${docker_cmd:+${docker_cmd} }"-v $(readlink -f ${KUSTOMIZE}):/home/build/customize"
fi
if [[ -n ${PACKAGES} ]]; then
    _cmd="${_cmd} PACKAGES=\"${PACKAGES}\""
fi

eval "${docker_cmd} ${DOCKER_IMAGE}-${VERSION} bash -c '${_cmd}'"

if [[ $(command -v qemu-img) ]]; then
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
    done < <(find "${BINDING}/targets/x86/64" -iname "*-combined*.img.gz" | sort)
fi
