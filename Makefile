all:
	@./build-live.sh create

install:
	@if [ -z "$(D)" ]; then \
	  echo "Usage:"; \
	  echo " make D=/dev/sdxn"; \
	  echo ""; \
	  exit 1; \
	 fi
	@./build-live.sh install $(D)

clean:
	@./build-live.sh clean

