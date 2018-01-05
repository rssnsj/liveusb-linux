create:
	@MAKE=$(MAKE) ./build-live.sh create

install:
	@if [ -z "$(D)" ]; then \
	  echo "Usage:"; \
	  echo " make D=/dev/sdxn"; \
	  echo ""; \
	  exit 1; \
	 fi
	@MAKE=$(MAKE) ./build-live.sh install $(D)

menuconfig:
	@./build-live.sh menuconfig

chroot:
	@./build-live.sh chroot || :

clean:
	@./build-live.sh clean

