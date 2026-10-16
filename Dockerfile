FROM php:8.3-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev \
    && docker-php-ext-install pdo_pgsql \
    && a2enmod headers rewrite \
    && rm -rf /var/lib/apt/lists/*

COPY deployment/apache-security.conf /etc/apache2/conf-available/mymatch-security.conf
RUN a2enconf mymatch-security

WORKDIR /var/www/html
COPY . /var/www/html
RUN mkdir -p /var/lib/mymatch/uploads \
    && chown -R www-data:www-data /var/lib/mymatch
