SHELL := /bin/bash
SRC := $(shell find . -type f -name '*.go' -not -path "./vendor/*")
PKG := $(shell go list -f {{.ImportPath}})
BIN := $(shell echo "$${PWD\#\#*/}")
BRANCH ?= $(shell git rev-parse --abbrev-ref HEAD)
COMMIT ?= $(shell git rev-parse HEAD)
VERSION ?= $(BRANCH)/$(COMMIT)
TAG ?= $(COMMIT)
REGION ?= ${AWS_DEFAULT_REGION}
PROFILE ?= ${AWS_PROFILE}
ACCOUNT ?= ${AWS_ACCOUNT_ID}
REGISTRY ?= $(ACCOUNT).dkr.ecr.$(REGION).amazonaws.com/les
IMG ?= $(REGISTRY)/$(BIN):$(TAG)
PORT ?= 8080
LDFLAGS ?= -ldflags "-X main.version=$(VERSION) -X main.build=$(shell date -u -Is)" # means non-reproducible builds, but handy for demonstration purposes
.DEFAULT_GOAL := build

.PHONY: all
all: env test install

# env prints go environment information
.PHONY: env
env:
	go env

# vet examines go source code and reports suspicious constructs
.PHONY: vet
vet:
	go tool vet -v $(SRC)

# fmt formats go programs
.PHONY: fmt
fmt: vet
	gofmt -e -l -s -w $(SRC)

# gometalinter concurrently runs a whole bunch of go linters and normalises their output to a standard format
.PHONY: lint
lint: fmt
	go get -v -u github.com/alecthomas/gometalinter
	gometalinter -i -u
	gometalinter --enable-all --disable=gas --deadline=60s -t $(SRC)

# test automates testing the packages named by the import paths
# cover produces test coverage reports
.PHONY: test
test: lint
	go test -v $(LDFLAGS) -coverprofile c.out $(PKG)
	go tool cover -html=c.out -o c.html

# build compiles the packages named by the import paths, along with their dependencies, but it does not install the results
$(BIN): $(SRC)
	go build -v -x $(LDFLAGS) -o $(BIN) $(PKG)

build: $(BIN)

# install compiles and installs the packages named by the import paths, along with their dependencies
.PHONY: install
install:
	go install -v -x $(LDFLAGS) $(PKG)

# go run
run: install
	$(BIN)

# clean removes object files from package source directories
.PHONY: clean
clean:
	go clean -x $(PKG)
	rm -f c.{out,html}
	rm -f README.html
	rm -rf .bundle reveal.js

# the -i flag causes clean to remove the corresponding installed archive or binary (what 'go install' would create)
.PHONY: uninstall
uninstall: clean
	go clean -x -i $(PKG)

# get downloads the packages named by the import paths, along with their dependencies
.PHONY: get
get:
	go get -v -u -t $(PKG)

# builds a docker image from a Dockerfile
.PHONY: docker-build
docker-build:
	docker build --build-arg BRANCH=$(BRANCH) --build-arg COMMIT=$(COMMIT) --build-arg PORT=$(PORT) -t $(IMG) .

# runs a command in a new docker container
.PHONY: docker-run
docker-run:
	docker run -d -e PORT=$(PORT) -p $(PORT):$(PORT) --rm $(IMG)

# pushes a docker image or a repository to a registry
.PHONY: docker-push
docker-push:
	eval $$(aws ecr get-login --no-include-email --profile $(PROFILE) --region $(REGION))
	docker push $(IMG)

reveal.js:
	bundle install --path .bundle
	curl -sSL https://github.com/hakimel/reveal.js/archive/3.5.0.tar.gz | tar -xz && mv reveal.js-*.*.* reveal.js
	curl -sSL https://raw.githubusercontent.com/isagalaev/highlight.js/master/src/styles/grayscale.css > reveal.js/lib/css/grayscale.css

README.html: README.asc reveal.js
	bundle exec asciidoctor-revealjs $(<)

deck: README.html
