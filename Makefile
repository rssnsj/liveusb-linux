build:
	@MAKE=$(MAKE) ./build-live.sh build_all

menuconfig:
	@./build-live.sh menuconfig

clean:
	@./build-live.sh clean
