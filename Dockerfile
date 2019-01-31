FROM golang:1.11-alpine as protoc_builder
RUN apk add --no-cache build-base curl automake autoconf libtool git zlib-dev
ARG GITHUB_TOKEN
ENV GRPC_VERSION=1.16.0 \
        PROTOBUF_VERSION=3.6.1 \
        PROTOC_GEN_DOC_VERSION=1.1.0 \
        OUTDIR=/out
RUN mkdir -p /protobuf && \
        curl -L https://github.com/google/protobuf/archive/v${PROTOBUF_VERSION}.tar.gz | tar xvz --strip-components=1 -C /protobuf
RUN git clone --depth 1 --recursive -b v${GRPC_VERSION} https://github.com/grpc/grpc.git /grpc && \
        rm -rf grpc/third_party/protobuf && \
        ln -s /protobuf /grpc/third_party/protobuf
RUN cd /protobuf && \
        autoreconf -f -i -Wall,no-obsolete && \
        ./configure --prefix=/usr --enable-static=no && \
        make && make install
RUN cd /protobuf && \
        make install DESTDIR=${OUTDIR}
RUN cd /grpc && \
        make install-plugins prefix=${OUTDIR}/usr
RUN find ${OUTDIR} -name "*.a" -delete -or -name "*.la" -delete

# RUN git config --global url."https://$GITHUB_TOKEN@github.com/".insteadOf "https://github.com/"
RUN go get -u -v -ldflags '-w -s' \
        github.com/Masterminds/glide \
        # github.com/golang/protobuf/protoc-gen-go@v1.2.0 \
        github.com/golang/protobuf/protoc-gen-go \
        github.com/gogo/protobuf/protoc-gen-gofast \
        github.com/gogo/protobuf/protoc-gen-gogo \
        github.com/gogo/protobuf/protoc-gen-gogofast \
        github.com/gogo/protobuf/protoc-gen-gogofaster \
        github.com/gogo/protobuf/protoc-gen-gogoslick \
        github.com/twitchtv/twirp/protoc-gen-twirp \
        github.com/chrusty/protoc-gen-jsonschema \
        github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger \
        github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway \
        github.com/johanbrandhorst/protobuf/protoc-gen-gopherjs \
        github.com/ckaznocha/protoc-gen-lint \
        github.com/mwitkow/go-proto-validators/protoc-gen-govalidators \
        moul.io/protoc-gen-gotemplate \
        github.com/micro/protoc-gen-micro \
        github.com/suntechsoft/dmarket-go-tools/queue-dispatcher/pb/protoc-gen-queue-dispatcher \
        github.com/suntechsoft/dmarket-go-tools/asyncly/cmd/protoc-gen-asyncly \
        github.com/suntechsoft/dmarket-go-tools/micro/wrap/microerr/cmd/protoc-gen-microerr \
        # github.com/suntechsoft/dmarket-go-tools/proto-importer \
        github.com/golang/mock/mockgen \
        && cd ${GOPATH}/src/github.com/golang/protobuf/protoc-gen-go && git checkout tags/v1.2.0 && go install . \
        && install -c ${GOPATH}/bin/protoc-gen* ${OUTDIR}/usr/bin/
RUN go get github.com/suntechsoft/dmarket-go-tools/proto-importer \
        && install -c ${GOPATH}/bin/proto-importer ${OUTDIR}/usr/bin/

RUN mkdir -p ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc && \
        curl -L https://github.com/pseudomuto/protoc-gen-doc/archive/v${PROTOC_GEN_DOC_VERSION}.tar.gz | tar xvz --strip 1 -C ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc
RUN cd ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc && \
        make build && \
        install -c ${GOPATH}/src/github.com/pseudomuto/protoc-gen-doc/protoc-gen-doc ${OUTDIR}/usr/bin/

FROM znly/upx as packer
COPY --from=protoc_builder /out/ /out/
RUN upx --lzma \
        /out/usr/bin/protoc \
        /out/usr/bin/proto-importer \
        /out/usr/bin/grpc_* \
        /out/usr/bin/protoc-gen-*

FROM alpine
RUN apk add --no-cache libstdc++
COPY --from=packer /out/ /
RUN apk add --no-cache curl make git && \
        mkdir -p /protobuf/google/protobuf && \
        for f in any duration descriptor empty struct timestamp wrappers; do \
        curl -L -o /protobuf/google/protobuf/${f}.proto https://raw.githubusercontent.com/google/protobuf/master/src/google/protobuf/${f}.proto; \
        done && \
        mkdir -p /protobuf/google/api && \
        for f in annotations http; do \
        curl -L -o /protobuf/google/api/${f}.proto https://raw.githubusercontent.com/grpc-ecosystem/grpc-gateway/master/third_party/googleapis/google/api/${f}.proto; \
        done && \
        mkdir -p /protobuf/github.com/gogo/protobuf/gogoproto && \
        curl -L -o /protobuf/github.com/gogo/protobuf/gogoproto/gogo.proto https://raw.githubusercontent.com/gogo/protobuf/master/gogoproto/gogo.proto && \
        mkdir -p /protobuf/github.com/mwitkow/go-proto-validators && \
        curl -L -o /protobuf/github.com/mwitkow/go-proto-validators/validator.proto https://raw.githubusercontent.com/mwitkow/go-proto-validators/master/validator.proto && \
        apk del curl

#ENTRYPOINT ["/usr/bin/protoc", "-I/protobuf"]
