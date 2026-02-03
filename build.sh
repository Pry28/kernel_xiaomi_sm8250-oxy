#!/bin/bash
# Original script by TIMISONG

# Telegram token
source token.sh

# Начало отсчета времени выполнения скрипта
start_time=$(date +%s)

# Удаление каталога "out", если он существует
rm -rf out

# Основной каталог
MAINPATH=/workspaces # измените, если необходимо

# Каталог ядра
KERNEL_DIR=$MAINPATH
KERNEL_PATH=$KERNEL_DIR/kernel_xiaomi_sm8250-oxy

git log $LAST..HEAD > ../changelog.txt
BRANCH=$(git branch --show-current)

# Каталоги компиляторов
CLANG_DIR=$KERNEL_DIR/clang20

# Проверка и клонирование, если необходимо
check_and_clone() {
    local dir=$1
    local repo=$2
    local name=$3

    if [ ! -d $dir ]; then
        echo Папка $dir не существует. Клонирование $repo
        cd $dir
        git clone $repo $name
    fi
}

check_and_wget() {
    local dir=$1
    local repo=$2

    if [ ! -d $dir ]; then
        echo Папка $dir не существует. Клонирование $repo
        mkdir $dir
        cd $dir
        wget -O clang.tar.gz $repo
        tar -zxvf clang.tar.gz
        rm -rf clang.tar.gz
        cd ../kernel_xiaomi_sm8250-oxy
    fi
}

# Клонирование инструментов компиляции, если они не существуют
check_and_wget $CLANG_DIR \
    https://github.com/ZyCromerZ/Clang/releases/download/20.0.0git-20250129-release/Clang-20.0.0git-20250129.tar.gz

# Каталог для сборки Oxygen+
OXY_DIR=$KERNEL_DIR/Oxy-munch

# Создание каталога OXY, если его нет
if [ ! -d $OXY_DIR ]; then
    mkdir -p $OXY_DIR
    
    # Проверка и клонирование Anykernel, если OXY не существует
    if [ ! -d $OXY_DIR/Anykernel ]; then
        git clone https://github.com/Olzhas-Kdyr/Anykernel.git \
            $OXY_DIR/Anykernel
        
        # Перемещение всех файлов из Anykernel в OXY
        mv $OXY_DIR/Anykernel/* $OXY_DIR/
        
        # Удаление папки Anykernel
        rm -rf $OXY_DIR/Anykernel
    fi
else
    # Если папка OXY существует, проверить наличие .git и удалить, если есть
    if [ -d $OXY_DIR/.git ]; then
        rm -rf $OXY_DIR/.git
    fi
fi

# Экспорт переменных среды
IMGPATH=$OXY_DIR/Image
DTBPATH=$OXY_DIR/dtb
DTBOPATH=$OXY_DIR/dtbo.img

# Установка переменных PATH
export PATH=$CLANG_DIR/bin:$GCC_AARCH64_DIR/bin:$GCC_ARM_DIR/bin:$PATH
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KBUILD_BUILD_USER=olzhas
export KBUILD_BUILD_HOST=ubuntu

# Запись времени сборки
OXY_BUILD_DATE=$(date '+%Y-%m-%d_%H-%M-%S')

# Каталог для результатов сборки
OUT_DIR=out

# Конфигурация ядра
make O="$OUT_DIR" \
            vendor/munch_defconfig

    # Компиляция ядра
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
                

# Предполагается, что переменная DTS установлена ранее в скрипте
find $DTS -name '*.dtb' -exec cat {} + > $DTBPATH
find $DTS -name 'Image' -exec cat {} + > $IMGPATH
find $DTS -name 'dtbo.img' -exec cat {} + > $DTBOPATH

# Завершение отсчета времени выполнения скрипта
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

cd "$KERNEL_PATH"

# Проверка успешности сборки
if grep -q -E "Ошибка 2|Error 2" build.log; then
    cd $KERNEL_PATH
    echo Ошибка: Сборка завершилась с ошибкой

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendMessage \
    -d chat_id=@olzkernel \
    -d text="Ошибка в компиляции!" \
    -d message_thread_id=3

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=@olzkernel \
    -F document=@./build.log \
    -F message_thread_id=3

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=@olzkernel \
    -F document=@../changelog.txt \
    -F message_thread_id=3
else
    echo Общее время выполнения: $elapsed_time секунд
    # Перемещение в каталог OXY и создание архива
    cd $OXY_DIR
    7z a -mx9 4.19.325-Oxygen+munch-$OXY_BUILD_DATE.zip * -x!*.zip
    
    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendMessage \
    -d chat_id=@olzkernel \
    -d text="Компиляция завершилась успешно! Время выполнения: $elapsed_time секунд" \
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
