SHELL := /bin/bash

.PHONY: build docker test clean

build:
	./build.sh

docker:
	docker build -t nginxconsul:local .

test:
	./test/smoke.sh

clean:
	rm -rf build dist
