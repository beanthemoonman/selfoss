FROM php:8.1-fpm

VOLUME /var/www/html/data/sqlite

# Install dependencies
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libzip-dev \
    libtidy-dev \
    unzip \
    nginx \
    curl \
    gnupg \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install pdo_mysql \
    && docker-php-ext-install zip \
    && docker-php-ext-install tidy \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js and npm
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get update \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . /var/www/html/

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader

# Install client dependencies and build assets
WORKDIR /var/www/html/client
RUN npm install
RUN npm run build
WORKDIR /var/www/html

# Generate config-example.ini
RUN php utils/generate-config-example.php

# Set up configuration
RUN cp config-example.ini config.ini

# Set proper permissions for data directories
RUN mkdir -p data/cache data/favicons data/logs data/thumbnails data/sqlite \
    && chown -R www-data:www-data data

# Configure Nginx
RUN echo "server {\n\
    listen 80;\n\
    server_name localhost;\n\
    root /var/www/html;\n\
    location ~* \ (gif|jpg|png) {\n\
      expires 30d;\n\
    }\n\
    location ~ ^/(favicons|thumbnails)/.*$ {\n\
      try_files \$uri /data/\$uri;\n\
    }\n\
    location ~* ^/(data\/logs|data\/sqlite|config\.ini) {\n\
      deny all;\n\
    }\n\
    location / {\n\
      index index.php;\n\
      try_files \$uri /public/\$uri /index.php\$is_args\$args;\n\
    }\n\
    location ~ \.php$ {\n\
        fastcgi_pass 127.0.0.1:9000;\n\
        fastcgi_index index.php;\n\
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\n\
        include fastcgi_params;\n\
    }\n\
}" > /etc/nginx/sites-available/default

# Create start script
RUN echo '#!/bin/bash\n\
service nginx start\n\
php-fpm\n\
' > /start.sh && chmod +x /start.sh

# Expose port
EXPOSE 80

# Start services
CMD ["/start.sh"]
