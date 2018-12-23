

NAME=ws2812svr
DESC="ws2812 light server"
PKGNAME=ati-${NAME}

VERSION=0.0.1
BUILD_NUMBER_FILE=.buildnum
BUILD_NUMBER=$$(cat $(BUILD_NUMBER_FILE))
ARCH=armhf
UNITFILE=$(NAME).service
BUILDTMP="/tmp/build_$(NAME)"

BUILDDATE=`date +%Y%m%d.%H%M%S`
BUILDHOST=`hostname`
BUILDUSER=`id -u -n`
PKGFILE="${PKGNAME}${PKGREV}_${VERSION}_${ARCH}.deb"
GITHASH=`git rev-parse HEAD`
GITBRANCH=`git rev-parse --abbrev-ref HEAD`

all: $(UNITFILE) $(NAME)


INCL=-I/usr/include
LINK=-L/usr/lib -L/usr/local/lib -I/usr/lib/arm-linux-gnueabihf -lpthread
CC=gcc -g $(INCL)

ifneq (1,$(NO_PNG))
  CC += -DUSE_PNG
  LINK += -lpng
endif

ifneq (1,$(NO_JPEG))
  CC += -DUSE_JPEG
  LINK += -ljpeg
endif

dma.o: dma.c dma.h
	$(CC) -c $< -o $@

mailbox.o: mailbox.c mailbox.h
	$(CC) -c $< -o $@
	
pwm.o: pwm.c pwm.h ws2811.h
	$(CC) -c $< -o $@
	
pcm.o: pcm.c pcm.h
	$(CC) -c $< -o $@

rpihw.o: rpihw.c rpihw.h
	$(CC) -c $< -o $@

ifneq (1,$(NO_PNG))
readpng.o: readpng.c readpng.h
	$(CC) -c $< -o $@
endif

ws2811.o: ws2811.c ws2811.h rpihw.h pwm.h pcm.h mailbox.h clk.h gpio.h dma.h rpihw.h readpng.h
	$(CC) -c $< -o $@

main.o: main.c ws2811.h
	$(CC) -c $< -o $@

ifneq (1,$(NO_PNG))
$(NAME): main.o dma.o mailbox.o pwm.o pcm.o ws2811.o rpihw.o readpng.o
	$(CC) $(LINK) $^ -o $@
else
$(NAME): main.o dma.o mailbox.o pwm.o pcm.o ws2811.o rpihw.o
	$(CC) $(LINK) $^ -o $@
endif

clean:
	rm *.o
	rm $(NAME)
	rm ${PKGNAME}-linux-armhf.deb


## keep track of our build number

.PHONY: $(BUILD_NUMBER_FILE)
$(BUILD_NUMBER_FILE):
	@if ! test -f $(BUILD_NUMBER_FILE); then echo 0 > $(BUILD_NUMBER_FILE); fi
	@echo $$(($$(cat $(BUILD_NUMBER_FILE)) + 1)) > $(BUILD_NUMBER_FILE)

## generate a systemd unitfile if one does not already exist

ifneq ("$(wildcard $(UNITFILE))","")
$(UNITFILE):
	@echo "$(UNITFILE) already exisits"
else
$(UNITFILE):
	@echo "Generating systemd unit file $(UNITFILE)"
	@echo "[Unit]" > $@
	@echo "Description=$(DESC)" >> $@
	@echo "After=network.target" >> $@
	@echo "" >> $@
	@echo "[Service]" >> $@
	@echo "SyslogIdentifier=$(NAME)" >> $@
	@echo "ExecStart=/usr/sbin/$(NAME)" >> $@
	@echo "Restart=always" >> $@
	@echo "RestartSec=3" >> $@
	@echo "" >> $@
	@echo "[Install]" >> $@
	@echo "WantedBy=multi-user.target" >> $@
endif

install:
	cp ${UNITFILE} /etc/systemd/system/
	chmod 664 /etc/systemd/system/${UNITFILE}
	systemctl daemon-reload
	systemctl enable ${UNITFILE}

uninstall:
	systemctl stop ${UNITFILE}
	systemctl disable ${UNITFILE}
	rm /etc/systemd/system/${UNITFILE}
	systemctl daemon-reload

restart:
	systemctl restart ${UNITFILE}

start:
	systemctl start ${UNITFILE}

stop:
	systemctl stop ${UNITFILE}


pi-build-deps:
	apt-get update && apt-get install build-essential make  libjpeg-dev libpng-dev ruby ruby-dev
	gem install fpm

debian_armhf_pkg: $(NAME) $(UNITFILE)
	@echo "Building ${PKGFILE}-linux-armhf ..."
	-@rm -rf ${BUILDTMP}
	-@rm -rf ${PKGNAME}-linux-armhf.deb
	@mkdir -p ${BUILDTMP}/usr/sbin
	@cp ${NAME} ${BUILDTMP}/usr/sbin
	@fpm -s dir -C ${BUILDTMP} \
		-a armhf \
		-m "David Sharp <dsharp@actiontarget.com>" \
		--description $(DESC) \
		--url "https://github.com/tom-2015/rpi-ws2812-server" \
		--vendor "Tom-2015" \
		--deb-priority optional \
		--depends libjpeg-dev \
		--depends libpng-dev \
		-v "${VERSION}-${BUILD_NUMBER}" \
		-t deb \
		-n ${PKGNAME} \
		-p ${PKGNAME}-linux-armhf.deb \
		--deb-systemd ${UNITFILE}
	@echo ""
	@dpkg --info ${PKGNAME}-linux-armhf.deb


add_to_repository:
	scp ${PKGNAME}-linux-armhf.deb root@action-target.net:/home/pkg/packages/${PKGNAME}-linux-armhf.deb
	ssh root@action-target.net "dpkg-sig --sign builder /home/pkg/packages/${PKGNAME}-linux-armhf.deb"
	ssh root@action-target.net "(cd /home/pkg/repo; reprepro --ask-passphrase -Vb . includedeb jessie /home/pkg/packages/${PKGNAME}-linux-armhf.deb)"

