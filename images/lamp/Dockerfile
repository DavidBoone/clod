# PHP with common extensions, Composer, Apache with mod_php, and MariaDB.
ARG BASE=clod
FROM $BASE
USER root
RUN apt-get install -y \
       php-cli php-mysql php-sqlite3 php-mbstring php-xml php-curl \
       php-gd php-intl php-zip php-bcmath \
       composer apache2 libapache2-mod-php mariadb-server
USER claude
