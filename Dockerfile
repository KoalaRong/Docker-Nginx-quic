FROM golang:alpine as boringssl_builder

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	&& apk --no-cache upgrade \
	&& apk add --no-cache --virtual .build-deps \
	gcc libc-dev perl-dev git cmake make g++ libunwind-dev linux-headers musl-dev musl-utils \
	&& mkdir -p /usr/local/src \
	&& git clone --depth=1 https://gitee.com/koalarong/boringssl.git /usr/local/src/boringssl \
	&& cd /usr/local/src/boringssl \
	&& mkdir build && cd build && cmake .. \
	&& make -j$(getconf _NPROCESSORS_ONLN) && cd ../ \
	&& mkdir -p .openssl/lib && cd .openssl && ln -s ../include . && cd ../ \
	&& cp build/crypto/libcrypto.a build/ssl/libssl.a .openssl/lib 

FROM alpine:latest as nginx_builder

ENV NGINX_VERSION 1.19.0
ENV LUAJIT2_VERSION 2.1-20200102
ENV NGX_DEVEL_KIT 0.3.1
ENV LUA_NGINX_MODULE 0.10.15


WORKDIR /usr/local/src
COPY ./patch/Enable_BoringSSL_OCSP.patch Enable_BoringSSL_OCSP.patch

COPY --from=boringssl_builder /usr/local/src/boringssl  ./boringssl

RUN set -x \
	# use tuna mirrors
	&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	# create nginx user/group first, to be consistent throughout docker variants
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
	make \
	pcre-dev \
	zlib-dev \
	openssl-dev \
	linux-headers \
	libxslt-dev \
	libunwind-dev \
	gd-dev \
	geoip-dev \
	perl-dev \
	libedit-dev \
	mercurial \
	alpine-sdk \
	findutils \
	build-base \
	wget \
	&& wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
	&& tar -zxC /usr/local/src -f nginx-$NGINX_VERSION.tar.gz \
	&& rm nginx-$NGINX_VERSION.tar.gz \
	# make lua-nginx-module
	&& wget https://github.com/openresty/luajit2/archive/v${LUAJIT2_VERSION}.tar.gz \
	&& wget https://github.com/vision5/ngx_devel_kit/archive/v${NGX_DEVEL_KIT}.tar.gz \
	&& wget https://github.com/openresty/lua-nginx-module/archive/v${LUA_NGINX_MODULE}.tar.gz \
	&& tar -xzf v${LUAJIT2_VERSION}.tar.gz && tar -xzf v${NGX_DEVEL_KIT}.tar.gz && tar -xzf v${LUA_NGINX_MODULE}.tar.gz \
	&& cd luajit2-${LUAJIT2_VERSION} \
	&& make -j$(getconf _NPROCESSORS_ONLN) PREFIX=/usr/local/src/luajit \
	&& make install PREFIX=/usr/local/src/luajit \
	&& export LUAJIT_LIB=/usr/local/src/luajit/lib \
	&& export LUAJIT_INC=/usr/local/src/luajit/include/luajit-2.1 \
	# ngx_brotli
	&& git clone --depth=1  https://github.com/google/ngx_brotli.git /usr/local/src/ngx_brotli \
	&& cd /usr/local/src/ngx_brotli \
	&& git submodule update --init \	
	# make nginx
	&& cd /usr/local/src/nginx-$NGINX_VERSION \
	&& patch -p1 < /usr/local/src/Enable_BoringSSL_OCSP.patch \
	&& ./configure \
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
	--with-mail \
	--with-mail_ssl_module \
	--with-stream \
	--with-stream_realip_module \
	--with-stream_ssl_module \
	--with-stream_ssl_preread_module\
	--with-http_xslt_module=dynamic \
	--with-http_image_filter_module=dynamic \
	--with-http_geoip_module=dynamic \
	--with-stream \
	--with-stream_ssl_module \
	--with-stream_ssl_preread_module \
	--with-stream_realip_module \
	--with-stream_geoip_module=dynamic \
	--with-pcre-jit \
	--with-openssl=/usr/local/src/boringssl/ \
	--with-ld-opt='-Wl,-rpath,/usr/local/src/luajit/lib' \
	--with-cc-opt='-Os -fomit-frame-pointer -DNGX_LUA_USE_ASSERT -DNGX_LUA_ABORT_AT_PANIC' \
	--add-module=/usr/local/src/ngx_brotli \
	--add-module=/usr/local/src/ngx_devel_kit-${NGX_DEVEL_KIT} \
	--add-module=/usr/local/src/lua-nginx-module-${LUA_NGINX_MODULE} \
	&& touch /usr/local/src/boringssl/.openssl/include/openssl/ssl.h \
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

FROM alpine:latest

ENV NGINX_VERSION 1.18.0

COPY --from=nginx_builder /etc/nginx /etc/nginx
COPY --from=nginx_builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=nginx_builder /usr/lib/nginx/modules/ /usr/lib/nginx/modules/
COPY --from=nginx_builder /usr/share/nginx/html/ /usr/share/nginx/html/
COPY --from=nginx_builder /usr/local/src/luajit /usr/local/src/luajit

RUN set -x \
	&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	&& apk --no-cache upgrade \
	# create nginx user/group first, to be consistent throughout docker variants
	&& export LUAJIT_LIB=/usr/local/src/luajit/lib \
	&& export LUAJIT_INC=/usr/local/src/luajit/include/luajit-2.1 \
	&& addgroup -g 101 -S nginx \
	&& adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx \
	# Bring in gettext so we can get `envsubst`, then throw
	# the rest away. To do this, we need to install `gettext`
	# then move `envsubst` out of the way so `gettext` can
	# be deleted completely, then move `envsubst` back.
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
	# forward request and error logs to docker log collector
	&& ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log \
	&& nginx -V 

COPY conf/nginx.conf /etc/nginx/nginx.conf
# COPY conf/nginx.vh.default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80 443

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]