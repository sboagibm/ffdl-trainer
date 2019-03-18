#---------------------------------------------------------------#
#                                                               #
# IBM Confidential                                              #
# OCO Source Materials                                          #
#                                                               #
# (C) Copyright IBM Corp. 2016, 2017                            #
#                                                               #
# The source code for this program is not published or          #
# otherwise divested of its trade secrets, irrespective of      #
# what has been deposited with the U.S. Copyright Office.       #
#                                                               #
#---------------------------------------------------------------#

DOCKER_IMG_NAME = trainer-v2-service

include ../ffdl-commons/ffdl-commons.mk

# Rate limiter proto is a plugin, so we don't need/want REPO or VERSION
RATELIMITER_LOCATION ?= plugins/ratelimiter
RATELIMITER_SUBDIR ?= service/grpc_ratelimiter_v1
RATELIMITER_PROTO_LOC ?= plugins/ratelimiter
RATELIMITER_FNAME ?= ratelimiter

TOOLCHAIN_DOCKER_HOST ?= docker.io
TOOLCHAIN_DOCKER_NAMESPACE ?= ffdl
TOOLCHAIN_DOCKER_IMG_NAME ?= ffdlbuildtools
TOOLCHAIN_IMAGE_TAG ?= v1

# === Health Checker Sub Build ===

build-health-checker-deps: clean-health-checker-builds
	mkdir build
	cp -r vendor/github.com/AISphere/ffdl-commons/grpc-health-checker build/
	cd build/grpc-health-checker && make build-x86-64

clean-ratelimiter:                     ## clean ratelimiter artifacts
	rm -rf $(RATELIMITER_LOCATION)/$(RATELIMITER_SUBDIR)

protoc-ratelimiter:  clean-ratelimiter ## Make the rate limiter plugin client, depends on `make glide` being run first
	rm -rf $(RATELIMITER_LOCATION)/$(RATELIMITER_SUBDIR)
	mkdir -p $(RATELIMITER_LOCATION)/$(RATELIMITER_SUBDIR)
	protoc -I./$(RATELIMITER_PROTO_LOC) --go_out=plugins=grpc:$(RATELIMITER_LOCATION)/$(RATELIMITER_SUBDIR) ./$(RATELIMITER_PROTO_LOC)/$(RATELIMITER_FNAME).proto
	@# At the time of writing, protoc does not support custom tags, hence use a little regex to add "bson:..." tags
	@# See: https://github.com/golang/protobuf/issues/52
	cd $(RATELIMITER_LOCATION); \
	sed -i.bak '/.*bson:.*/! s/json:"\([^"]*\)"/json:"\1" bson:"\1"/' ./$(RATELIMITER_SUBDIR)/$(RATELIMITER_FNAME).pb.go

protoc: protoc-lcm protoc-tds          ## Make gRPC proto clients, depends on `make glide` being run first

install-deps: protoc-ratelimiter install-deps-base protoc build-health-checker-deps  ## Remove vendor directory, rebuild dependencies

glide-update: protoc-ratelimiter glide-update-base protoc       ## Run full glide rebuild

diagnose-target-build:
	@echo "Calling docker-build-base"

diagnose-target-push:
	@echo "Calling docker-push-base"

docker-build: diagnose-target-build docker-build-base        ## Install dependencies if vendor folder is missing, build go code, build docker image

docker-push: diagnose-target-push docker-push-base          ## Push docker image to a docker hub

clean-health-checker-builds:
	rm -rf ./build
	rm -rf ./controller/build
	rm -rf ./jmbuild/build

clean: clean-base clean-ratelimiter clean-health-checker-builds   ## clean all build artifacts
	rm -rf build; \
	rm -f ./$(RATELIMITER_SUBDIR)/$(RATELIMITER_FNAME).pb.go

docker-build-toolchain-container:  ## build docker container for running the build
	(cd toolchain && docker build --label git-commit=$(shell git rev-list -1 HEAD) -t "$(TOOLCHAIN_DOCKER_HOST)/$(TOOLCHAIN_DOCKER_NAMESPACE)/$(TOOLCHAIN_DOCKER_IMG_NAME):$(TOOLCHAIN_IMAGE_TAG)" .)

docker-push-toolchain-container:  ## build docker container for running the build
	docker push "$(TOOLCHAIN_DOCKER_HOST)/$(TOOLCHAIN_DOCKER_NAMESPACE)/$(TOOLCHAIN_DOCKER_IMG_NAME):$(TOOLCHAIN_IMAGE_TAG)"

toolchain-container: docker-build-toolchain-container docker-push-toolchain-container ## Build and push toolchain-container

undeploy-service:
	kubectl delete -f helmdeploy_rendered/ffdl-trainer/templates/services/trainer-service.yaml; \
	kubectl delete -f helmdeploy_rendered/ffdl-trainer/templates/services/trainer-deployment.yaml

deploy-service:
	kubectl apply -f helmdeploy_rendered/ffdl-trainer/templates/services/trainer-deployment.yaml -f helmdeploy_rendered/ffdl-trainer/templates/services/trainer-service.yaml

redeploy-service: undeploy-service deploy-service

rebuild-service: docker-build docker-push redeploy-service cli-grpc-config
