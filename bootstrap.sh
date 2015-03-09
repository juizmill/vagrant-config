#!/usr/bin/env bash

ProjectName=“NOME DA PASTA“ #Pasta do projeto
PathPublic=“NOME DO DOCUMENT ROOT“ # document root do sistema
DataBase=“NOME DA BASE DE DADOS“ #Nome da base de dados

#Logando como sudo SU
sudo su

echo ">>> ADD NAMESERVER DO GOOGLE <<<"
sudo echo > /etc/resolv.conf
sudo echo "nameserver 8.8.8.8" > /etc/resolv.conf

# verifica se o arquivo swap nao existe
grep -q "swapfile" /etc/fstab
if [ $? -ne 0 ]; then
    echo ">>> Cria SWAP <<<"
    sudo dd if=/dev/zero of=/swapfile bs=1024 count=512k
    sudo mkswap /swapfile
    sudo swapon /swapfile
    sudo echo "/swapfile       none    swap    sw      0       0 " >> /etc/fstab
    sudo chown vagrant:vagrant /swapfile
    sudo chmod 0600 /swapfile
fi

# Timezone do sistema
sudo cp -p /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
echo "America/Sao_Paulo" | sudo tee /etc/timezone

# Locale do sistema
echo -e "en_US.UTF-8 UTF-8\npt_BR ISO-8859-1\npt_BR.UTF-8 UTF-8" | sudo tee /var/lib/locales/supported.d/local
sudo dpkg-reconfigure locales

# Ignore the post install questions
export DEBIAN_FRONTEND=noninteractive

# Define diretiva que permitirá atualizar o grub sem ter que selecionar qual a partição de instalação (o ubuntu 14.04 atualiza o grub sozinho ao rodar 'upgrade')
sudo echo "set grub-pc/install_devices /dev/sda" | debconf-communicate

# Define diretivas que permitirão instalar MySQL sem perguntar senha
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password root'
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password root'

sudo apt-get update
sudo apt-get install -y python-software-properties

#Pacote PHP 5.5 ou 5.4
#PHP5.5 sudo add-apt-repository ppa:ondrej/php5
sudo add-apt-repository -y ppa:ondrej/php5-5.6
sudo apt-get update -y && sudo apt-get upgrade -y

# instala o suporte a NFS (sem ele o Vagrant fica uma carroça)
# Notas:
# - para usarmos Vagrant com NFS é necessário que tanto host quanto guest tenham suporte instalado.
# - no host, rode: sudo apt-get install nfs-common nfs-kernel-server portmap (note o nfs-common nfs-kernel-server que o guest não tem)
# - embora tenha colocado o pacote 'portmap', o apt-get instalou o pacote 'rpcbind' em seu lugar.
sudo apt-get install nfs-common portmap -y

#instalando PHP
sudo apt-get install -y php5 build-essential g++ git-core \
apache2 \
php5-cli \
php5-xdebug \
php-apc \
php5-curl \
php5-gd \
php5-imagick \
php5-mssql \
php-pear \
php5-cli \
php5-json \
php5-mcrypt \
php5-intl \
php5-memcached  \
php5-memcache \
memcached \
php5-dev \
libyaml-dev \
php5-mysql \
php5-imap \
php5-sqlite \
php5-common \
php5-pspell \
php5-recode \
php5-tidy \
php5-xmlrpc \
php5-xsl \
mysql-server

# Configurando MYSQL
sudo sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
sudo mysql --password=root -u root --execute="GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'root' WITH GRANT OPTION; FLUSH PRIVILEGES;"
sudo service mysql restart
sudo mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS $DataBase";

#Criando pasta
sudo mkdir /data
sudo mkdir /data/db
sudo chmod -R 777 /data/db
sudo service mongod restart

#Adicionais
sudo apt-get install -y vim

# Em produção descomentar xdebue e comentar opcache
#sudo php5dismod -s cli xdebug
sudo php5dismod -s cli opcache

# Configura xdebug
cat << EOF | sudo tee -a /etc/php5/cli/conf.d/20-xdebug.ini
xdebug.scream=0
xdebug.cli_color=1
xdebug.show_local_vars=1
xdebug.max_nesting_level=250
xdebug.idekey="PHPSTORM"
EOF

# Apache config
echo -e "\n# configuracoes personalizadas\nServerTokens ProductOnly\nServerSignature Off" | sudo tee -a /etc/apache2/apache2.conf
sudo sed -i 's/User ${APACHE_RUN_USER}/User vagrant/g' /etc/apache2/apache2.conf
sudo sed -i 's/Group ${APACHE_RUN_GROUP}/Group vagrant/g' /etc/apache2/apache2.conf

sudo echo > /etc/apache2/sites-available/$ProjectName.conf
cat << EOF | sudo tee -a /etc/apache2/sites-available/$ProjectName.conf
 <VirtualHost *:80>
    ServerName localhost
    ServerAdmin webmaster@localhost
    DocumentRoot "/vagrant/$PathPublic"
    SetEnv APPLICATION_ENV development
    SetEnv APPLICATION_PATH /vagrant/
    <Directory "/vagrant/$PathPublic">
        DirectoryIndex index.php
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog /vagrant/error.log
    # Possible values include: debug, info, notice, warn, error, crit,
    # alert, emerg.
    LogLevel warn
    ServerSignature On
    CustomLog /vagrant/access.log combined
</VirtualHost>
EOF

# PHP Config

# Exiba todos os erros
sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL | E_STRICT/" /etc/php5/cli/php.ini
sudo sed -i "s/display_errors = .*/display_errors = On/" /etc/php5/cli/php.ini

# Aumenta a quantidade limite de memória
sudo sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php5/cli/php.ini

# Aumenta o tempo máximo de execução de cada script
sudo sed -i "s/max_execution_time = .*/max_execution_time = 120/" /etc/php5/cli/php.ini

# Não expoe a versão do PHP no header da response.
sudo sed -i "s/expose_php = .*/expose_php = Off/" /etc/php5/cli/php.ini

# tempo que o servidor guarda os dados da sessão antes de enviar para o Garbage Collection
sudo sed -i "s/session.cookie_lifetime = .*/session.cookie_lifetime = 172800/" /etc/php5/cli/php.ini # 2 dias em segundos

# tempo de expiração do cookie PHPSSESIONID
sudo sed -i "s/gc_maxlifetime = .*/gc_maxlifetime = 172800/" /etc/php5/cli/php.ini # 2 dias em segundos

# TIMEZONE == O -r a baixo é pro sed aceitar ?: http://stackoverflow.com/questions/6156259/sed-expression-dont-allow-optional-grouped-string
sudo sed -r -i "s/;date.timezone =.*/date.timezone = America\/Sao_Paulo/" /etc/php5/cli/php.ini

# Habilita short open tags (<? ?>)
sudo sed -i "s/short_open_tag = .*/short_open_tag = On/" /etc/php5/cli/php.ini

# Aumenta o tamanho máximo dos uploads para 100MB
sudo sed -i "s/post_max_size = .*/post_max_size = 100M/" /etc/php5/cli/php.ini # 2 dias em segundos
sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 100M/" /etc/php5/cli/php.ini # 2 dias em segundos

sudo a2dissite 000-default
sudo a2ensite $ProjectName
sudo a2enmod rewrite
sudo service apache2 restart

# Composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# Ao efetuar login (vagrant ssh), já entra no diretório '/vagrant'
echo "cd /vagrant" | sudo tee -a /home/vagrant/.bashrc
