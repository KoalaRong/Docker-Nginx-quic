ARG ALPINE_VERSION="3.18"

FROM golang:alpine${ALPINE_VERSION} as boringssl_builder

ARG HTTP_PROXY="http://192.168.70.116:7890"
ARG HTTPS_PROXY="http://192.168.70.116:7890"

RUN set -x \
	# use tuna mirrors 
	#&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	# use goproxy
	&& go env -w GO111MODULE=on \
	&& go env -w GOPROXY=https://goproxy.cn,direct \
	&& apk update \
	&& apk --no-cache upgrade \
	&& apk add --no-cache --virtual .build-deps \
	git cmake samurai libstdc++ build-base perl-dev linux-headers libunwind-dev \
	&& mkdir -p /usr/local/src \
	&& git clone --depth=1 -b master https://github.com/google/boringssl.git /usr/local/src/boringssl \
	&& cd /usr/local/src/boringssl \
	&& mkdir build \
    && cd build \
    && cmake -GNinja .. \
    && ninja \
    && ls -la \
    && ls -la ../include \
    && apk del --no-network .build-deps

FROM alpine:${ALPINE_VERSION} as nginx_builder

ARG HTTP_PROXY="http://192.168.70.116:7890"
ARG HTTPS_PROXY="http://192.168.70.116:7890"
ARG NGINX_VERSION="1.25.2"
# https://nginx.org/en/download.html

WORKDIR /usr/local/src

RUN --mount=type=bind,from=boringssl_builder,source=/usr/local/src/boringssl,target=/usr/local/src/boringssl \
    set -x \
	# use tuna mirrors
	#&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	&& apk update \
	&& apk --no-cache upgrade \
	&& apk add --no-cache --virtual .build-deps \
	bash \
	binutils \
	libgcc \
	libstdc++ \
	libtool \
	su-exec \
	git \
	gcc \
	libc-dev \
	libunwind \
	make \
	pcre2-dev \
	zlib-dev \
	openssl-dev \
	linux-headers \
	libxslt-dev \
	gd-dev \
	geoip-dev \
	perl-dev \
	libedit-dev \
	mercurial \
	alpine-sdk \
	findutils \
	build-base \
	wget \
	# ngx_brotli
	&& git clone https://github.com/google/ngx_brotli.git /usr/local/src/ngx_brotli \
	&& cd /usr/local/src/ngx_brotli \
	&& git submodule update --init \
	# nginx	
	&& mkdir /usr/local/src/patch \
	&& wget https://raw.githubusercontent.com/kn007/patch/master/nginx_dynamic_tls_records.patch -O /usr/local/src/patch/nginx_dynamic_tls_records.patch \
	#&& wget https://hg.nginx.org/nginx-quic/archive/quic.tar.gz \
	#&& tar -zxC /usr/local/src -f quic.tar.gz \
	#&& rm quic.tar.gz \
	#&& cd /usr/local/src/nginx-quic-quic \
	&& wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
	&& tar -zxC /usr/local/src -f nginx-${NGINX_VERSION}.tar.gz \
	&& rm nginx-${NGINX_VERSION}.tar.gz \
	&& cd /usr/local/src/nginx-${NGINX_VERSION} \
	&& patch -p1 < /usr/local/src/patch/nginx_dynamic_tls_records.patch \
	#&& patch -p1 < /usr/local/src/patch/Enable_BoringSSL_OCSP.patch \
	&& ./configure \
	#--with-debug \
	--prefix=/etc/nginx \
	--sbin-path=/usr/sbin/nginx \
	--modules-path=/usr/lib/nginx/modules \
	--conf-path=/etc/nginx/nginx.conf \
	--error-log-path=/var/log/nginx/error.log \
	--http-log-path=/var/log/nginx/access.log \
	--pid-path=/var/run/nginx.pid \
	--lock-path=/var/run/nginx.lock \
	--http-client-body-temp-path=/var/cache/nginx/client_temp \
	--http-proxy-temp-path=/var/cache/nginx/proxy_temp \
	--http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
	--http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
	--http-scgi-temp-path=/var/cache/nginx/scgi_temp \
	--user=nginx \
	--group=nginx \
	--with-compat \
	--with-file-aio \
	--with-threads \
	--with-http_addition_module \
	--with-http_auth_request_module \
	--with-http_dav_module \
	--with-http_flv_module \
	--with-http_gunzip_module \
	--with-http_gzip_static_module \
	--with-http_mp4_module \
	--with-http_random_index_module \
	--with-http_realip_module \
	--with-http_secure_link_module \
	--with-http_slice_module \
	--with-http_ssl_module \
	--with-http_stub_status_module \
	--with-http_sub_module \
	--with-http_v2_module \
	--with-http_v3_module \
	--with-http_xslt_module=dynamic \
	--with-http_image_filter_module=dynamic \
	--with-http_geoip_module=dynamic \
	--with-mail \
	--with-mail_ssl_module \
	--with-stream \
	#--with-stream_quic_module \
	--with-stream_realip_module \
	--with-stream_ssl_module \
	--with-stream_ssl_preread_module\
	--with-stream_realip_module \
	--with-stream_geoip_module=dynamic \
	--with-pcre-jit \
	--with-ld-opt='-L../boringssl/build/ssl -L../boringssl/build/crypto -Wl,-z,relro -Wl,-z,now -fPIC -lrt ' \
	--with-cc-opt='-I../boringssl/include -m64 -O3 -g -DTCP_FASTOPEN=23 -ffast-math -march=native -flto -fstack-protector-strong -fomit-frame-pointer -fPIC -Wformat -Wdate-time -D_FORTIFY_SOURCE=2 ' \
	--add-module=/usr/local/src/ngx_brotli \
	&& make -j$(getconf _NPROCESSORS_ONLN) \
	&& make install \
	&& rm -rf /etc/nginx/html/ \
	&& mkdir /etc/nginx/conf.d/ \
	&& mkdir -p /usr/share/nginx/html/ \
	&& install -m644 html/index.html /usr/share/nginx/html/ \
	&& install -m644 html/50x.html /usr/share/nginx/html/ \
	&& ln -s ../../usr/lib/nginx/modules /etc/nginx/modules \
	&& strip /usr/sbin/nginx* \
	&& strip /usr/lib/nginx/modules/*.so 

COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY html/* /usr/share/nginx/html/

FROM alpine:${ALPINE_VERSION}

COPY --from=nginx_builder /etc/nginx /etc/nginx
COPY --from=nginx_builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=nginx_builder /usr/lib/nginx/modules/ /usr/lib/nginx/modules/
COPY --from=nginx_builder /usr/share/nginx/html/ /usr/share/nginx/html/
#COPY --from=nginx_builder /usr/local/lib/ /usr/local/lib/
#COPY --from=nginx_builder /usr/local/lib/libprofiler.so.* /usr/local/lib/libprofiler.so.0

RUN set -x \
	#&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	&& apk --no-cache upgrade \
	# create nginx user/group first, to be consistent throughout docker variants
	&& rm -rf /usr/local/src \
	&& addgroup -g 101 -S nginx \
	&& adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
	# Bring in gettext so we can get `envsubst`, then throw
	# the rest away. To do this, we need to install `gettext`
	# then move `envsubst` out of the way so `gettext` can
	# be deleted completely, then move `envsubst` back.
	&& apk update \
	&& apk --no-cache upgrade \
	&& apk add --no-cache --virtual .gettext gettext \
	&& mv /usr/bin/envsubst /tmp/ \
	&& mkdir -p /var/cache/nginx \
	&& mkdir -p /var/log/nginx \
	&& runDeps="$( \
	scanelf --needed --nobanner --format '%n#p' /usr/sbin/nginx /usr/lib/nginx/modules/*.so /tmp/envsubst \
	| tr ',' '\n' \
	| sort -u \
	| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	&& apk add --no-cache --virtual .nginx-rundeps $runDeps \
	&& apk del .gettext \
	&& mv /tmp/envsubst /usr/local/bin/ \
	# Bring in tzdata so users could set the timezones through the environment
	# variables
	&& apk add --no-cache tzdata \
	#&& apk add --no-cache --virtual .build-deps \
	#libstdc++ \
	#libunwind-dev \
	# forward request and error logs to docker log collector
	#&& mkdir /tmp/tcmalloc \
	#&& chmod 777 /tmp/tcmalloc \
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log 

EXPOSE 80 443

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]