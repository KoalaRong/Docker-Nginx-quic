FROM alpine:latest as nginx_builder

ENV NGINX_VERSION 1.21.2
#https://nginx.org/en/download.html

WORKDIR /usr/local/src
COPY ./patch ./patch

RUN set -x \
	# use tuna mirrors
	&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	# create nginx user/group first, to be consistent throughout docker variants
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
	&& wget https://www.openssl.org/source/openssl-3.0.0.tar.gz \
	&& tar -xzC /usr/local/src -f openssl-3.0.0.tar.gz \
	&& rm -f openssl-3.0.0.tar.gz \
	# ngx_brotli
	&& git clone https://github.com/google/ngx_brotli.git /usr/local/src/ngx_brotli \
	&& cd /usr/local/src/ngx_brotli \
	&& git submodule update --init \	
	# make nginx
	&& cd /usr/local/src/nginx-$NGINX_VERSION \
	&& patch -p1 < /usr/local/src/patch/nginx.patch \
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
	--with-openssl=/usr/local/src/openssl-3.0.0/ \
	--with-openssl-opt='zlib -march=native -Wl,-flto' \
	--with-ld-opt='-Wl,-z,relro -Wl,-z,now -fPIC -lrt ' \
	--with-cc-opt='-m64 -O3 -g -DTCP_FASTOPEN=23 -ffast-math -march=native -flto -fstack-protector-strong -fomit-frame-pointer -fPIC -Wformat -Wdate-time -D_FORTIFY_SOURCE=2 ' \
	--add-module=/usr/local/src/ngx_brotli \
	#&& touch /usr/local/src/boringssl/.openssl/include/openssl/ssl.h \
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

COPY --from=nginx_builder /etc/nginx /etc/nginx
COPY --from=nginx_builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=nginx_builder /usr/lib/nginx/modules/ /usr/lib/nginx/modules/
COPY --from=nginx_builder /usr/share/nginx/html/ /usr/share/nginx/html/

RUN set -x \
	&& sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
	# && apk --no-cache upgrade \
	# create nginx user/group first, to be consistent throughout docker variants
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
	&& ln -sf /dev/stderr /var/log/nginx/error.log 

COPY conf/nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 443

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]