#!/bin/bash
# Original script by TIMISONG

# Telegram token
source token.sh

# Start of script execution time countdown
start_time=$(date +%s)

# Remove the "out" directory if it exists
rm -rf out

# Main catalog
MAINPATH=/workspaces # измените, если необходимо

# Kernel directories
KERNEL_DIR=$MAINPATH
KERNEL_PATH=$KERNEL_DIR/kernel_xiaomi_sm8250-oxy

git log $LAST..HEAD > ../changelog.txt
BRANCH=$(git branch --show-current)

# Compiler directories
CLANG_DIR=$KERNEL_DIR/clang20

# Check and clone if necessary
check_and_clone() {
    local dir=$1
    local repo=$2
    local name=$3

    if [ ! -d $dir ]; then
        echo Folder $dir does not exist. Cloning $repo
        cd $dir
        git clone $repo $name
    fi
}

check_and_wget() {
    local dir=$1
    local repo=$2

    if [ ! -d $dir ]; then
        echo Folder $dir does not exist. Cloning $repo
        mkdir $dir
        cd $dir
        wget -O clang.tar.gz $repo
        tar -zxvf clang.tar.gz
        rm -rf clang.tar.gz
        cd ../kernel_xiaomi_sm8250-oxy
    fi
}

# Cloning compilation tools if they don't exist
check_and_wget $CLANG_DIR \
    https://github.com/ZyCromerZ/Clang/releases/download/20.0.0git-20250129-release/Clang-20.0.0git-20250129.tar.gz

# Oxygen+ compilation directory
OXY_DIR=$KERNEL_DIR/Oxy-munch

# Create the OXY directory if it does not exist
if [ ! -d $OXY_DIR ]; then
    mkdir -p $OXY_DIR
    
    # Checking and cloning Anykernel if OXY does not exist
    if [ ! -d $OXY_DIR/Anykernel ]; then
        git clone https://github.com/Olzhas-Kdyr/Anykernel.git \
            $OXY_DIR/Anykernel
        
        # Moving all files from Anykernel to OXY
        mv $OXY_DIR/Anykernel/* $OXY_DIR/
        
        # Deleting the Anykernel folder
        rm -rf $OXY_DIR/Anykernel
    fi
else
    # If the OXY folder exists, check for .git and delete it if it exists
    if [ -d $OXY_DIR/.git ]; then
        rm -rf $OXY_DIR/.git
    fi
fi

# Exporting environment variables
IMGPATH=$OXY_DIR/Image
DTBPATH=$OXY_DIR/dtb
DTBOPATH=$OXY_DIR/dtbo.img

# Setting PATH variables
export PATH=$CLANG_DIR/bin:$GCC_AARCH64_DIR/bin:$GCC_ARM_DIR/bin:$PATH
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KBUILD_BUILD_USER=olzhas
export KBUILD_BUILD_HOST=ubuntu

# Recording building time
OXY_BUILD_DATE=$(date '+%Y-%m-%d_%H-%M-%S')

# Directory for building results
OUT_DIR=out

# Kernel configuration
make O="$OUT_DIR" \
            vendor/munch_defconfig

    # Kernel compilation
    make -j $(nproc) \
                O="$OUT_DIR" \
                CC="ccache clang" \
                HOSTCC=gcc \
                LD=ld.lld \
                AS=llvm-as \
                AR=llvm-ar \
                NM=llvm-nm \
                OBJCOPY=llvm-objcopy \
                OBJDUMP=llvm-objdump \
                STRIP=llvm-strip \
                LLVM=1 \
                LLVM_IAS=1 \
                V=$VERBOSE 2>&1 | tee build.log
                

# It is assumed that the DTS variable is set earlier in the script
find $DTS -name '*.dtb' -exec cat {} + > $DTBPATH
find $DTS -name 'Image' -exec cat {} + > $IMGPATH
find $DTS -name 'dtbo.img' -exec cat {} + > $DTBOPATH

# End of script execution time countdown
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

cd "$KERNEL_PATH"

# Checking if the build was successful
if grep -q -E "Ошибка 2|Error 2" build.log; then
    cd $KERNEL_PATH
    echo Error: The build failed.

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendMessage \
    -d chat_id=@olzkernel \
    -d text="Compilation error!" \
    -d message_thread_id=3

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=@olzkernel \
    -F document=@./build.log \
    -F message_thread_id=3

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=@olzkernel \
    -F document=@../changelog.txt \
    -F message_thread_id=3
else
    echo Total execution time: $elapsed_time seconds
    # Moving to the OXY directory and creating an archive
    cd $OXY_DIR
    7z a -mx9 4.19.325-Oxygen+munch-$OXY_BUILD_DATE.zip * -x!*.zip
    
    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendMessage \
    -d chat_id=@olzkernel \
    -d text="Compilation completed successfully! Execution time: $elapsed_time seconds" \
    -d message_thread_id=3

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=@olzkernel \
    -F document=@./4.19.325-Oxygen+munch-$OXY_BUILD_DATE.zip \
    -F caption="Oxygen+ for POCO F4 | branch: ${BRANCH}" \
    -F message_thread_id=3
    
    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=@olzkernel \
    -F document=@../changelog.txt \
    -F caption="Latest changes" \
    -F message_thread_id=3

    rm -rf 4.19.325-Oxygen+munch-$OXY_BUILD_DATE.zip

    BUILD=$((BUILD + 1))

    cd $KERNEL_PATH
    LAST=$(git log -1 --format=%H)

    sed -i "s/LAST=.*/LAST=$LAST/" ../settings.sh
    sed -i "s/BUILD=.*/BUILD=$BUILD/" ../settings.sh
fi
