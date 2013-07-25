#!/bin/bash

function usage {
  echo "usage: `basename "$0"` target_directory"
  exit
}

if [ "$#" -ne 1 ]; then
  usage
fi

# Versions
# Note: If these are not GA versions, you may run into issues verifying the MD5 sums.
HTTPD_VER="2.4.6"
PHP_VER="5.5.1"
MARIA_DB_VER="5.5.32"

TARGET_DIR="$1"
if [ "$TARGET_DIR" == `basename $TARGET_DIR` ]; then
  TARGET_DIR="`pwd`/$TARGET_DIR"
fi

TIMESTAMP=`date "+%Y-%m-%d_at_%H-%M-%S"`
TMP_DIR="/tmp/`basename $TARGET_DIR`/$TIMESTAMP"

echo "About to setup environment in $TARGET_DIR. Hit any key to continue or CTRL-C to abort..."
read

function abort {
  EXIT_CODE="$1"
  ERROR_MESSAGE="$2"
  echo -e "\n$ERROR_MESSAGE"
  echo "Aborting environment setup."
  exit "$EXIT_CODE"
}

function download {
  SRC="$1"
  shift
  DEST="$1"
  if [ -z "$DEST" ]; then
    DEST=`basename $SRC`
  fi

  curl -L -s -q -o "$DEST" "$SRC"
  if [ "$?" -ne 0 ]; then
    abort 1 "Download of $DEST failed with curl exit code $?!"
  fi
}

function verify_md5 {
  FILENAME="$1"
  shift
  EXPECTED="$1"

  if [ `which md5` ]; then
    ACTUAL=`md5 -q $FILENAME`
  elif [ `which md5sum` ]; then
    ACTUAL=`md5sum $FILENAME | cut -d ' ' -f 1`
  else
    abort 2 "MD5 Digest command not found. Unable to verify package integrity!"
  fi

  if [ "$EXPECTED" != "$ACTUAL" ]; then
    abort 3 "MD5 Digest for $FILENAME is invalid! Expected '$EXPECTED' but got '$ACTUAL'."
  fi
}

echo -n "Creating scratch directory $TMP_DIR... "
mkdir -p "$TMP_DIR"
echo "complete."
echo

cd "$TMP_DIR"

# Apache
APACHE_MIRRORS_FILE="apache-mirrors.txt"
echo -n "Determining Apache mirrors to use... "
download 'http://www.apache.org/dyn/closer.cgi' "$APACHE_MIRRORS_FILE"
APACHE_MIRROR=`grep -A 2 'We suggest the following mirror' "$APACHE_MIRRORS_FILE" | tail -n 1 | awk '{ print $2 }' | cut -d \" -f 2`
APACHE_BACKUP_MIRROR=`grep -A 1 'verify your downloads or if no other mirrors are working.' "$APACHE_MIRRORS_FILE" | tail -n 1 | awk '{ print $3 }' | cut -d \" -f 2`
echo "complete."

echo
echo "Using mirror $APACHE_MIRROR for source code packages."
echo "Using mirror $APACHE_BACKUP_MIRROR for package verification."
echo

echo -n "Downloading Apache HTTP Server $HTTPD_VER package... "
HTTPD_BASE="httpd-$HTTPD_VER"
HTTPD_ARCHIVE="$HTTPD_BASE.tar.gz"
download "$APACHE_MIRROR/httpd/$HTTPD_ARCHIVE"
echo "complete."

echo -n "Verifying integrity of Apache HTTP Server $HTTPD_VER package... "
download "$APACHE_BACKUP_MIRROR/httpd/$HTTPD_ARCHIVE.md5"
verify_md5 "$HTTPD_ARCHIVE" "`awk '{ print $1 }' $HTTPD_ARCHIVE.md5`"
echo "complete."

echo -n "Downloading Apache HTTP Server $HTTPD_VER APR and APR-Util package... "
HTTPD_APR_ARCHIVE="$HTTPD_BASE-deps.tar.gz"
download "$APACHE_MIRROR/httpd/$HTTPD_APR_ARCHIVE"
echo "complete."

echo -n "Verifying integrity of Apache HTTP Server $HTTPD_VER APR and APR-Util package... "
download "$APACHE_BACKUP_MIRROR/httpd/$HTTPD_APR_ARCHIVE.md5"
verify_md5 "$HTTPD_APR_ARCHIVE" "`awk '{ print $1 }' $HTTPD_APR_ARCHIVE.md5`"
echo "complete."
echo

# PHP
echo -n "Downloading PHP $PHP_VER package... "
PHP_BASE="php-$PHP_VER"
PHP_ARCHIVE="$PHP_BASE.tar.gz"
PHP_MIRRORS_FILE="php-mirrors.txt"
download "http://php.net/get/$PHP_ARCHIVE/from/a/mirror" "$PHP_MIRRORS_FILE"
PHP_MIRROR_LINE=`grep -A 1 caret "$PHP_MIRRORS_FILE" | head -n 2 | tail -1`
PHP_HOSTNAME=`echo "$PHP_MIRROR_LINE" | awk -F '">|</a' '{ print $2 }'`
PHP_PATH=`echo "$PHP_MIRROR_LINE" | cut -d \" -f 2`
download "http://$PHP_HOSTNAME$PHP_PATH" "$PHP_ARCHIVE"
echo "complete."

echo -n "Verifying integrity of PHP $PHP_VER package... "
download "http://php.net/downloads.php"
verify_md5 "$PHP_ARCHIVE" "`grep -A 1 \"$PHP_VER (tar.gz)\" downloads.php | tail -n 1 | awk '{ print $3 }' | cut -d '<' -f 1`"
echo "complete."
echo

# MariaDB
echo -n "Downloading MariaDB $MARIA_DB_VER package..."
MARIA_DB_RELEASE_NUM_FILE='maria_db_release.html'
download "https://downloads.mariadb.org/mariadb/$MARIA_DB_VER/" "$MARIA_DB_RELEASE_NUM_FILE"
MARIA_DB_RELEASE=`grep data-release "$MARIA_DB_RELEASE_NUM_FILE" | cut -d \" -f 2`
MARIA_DB_RELEASE_DETAIL='maria_db_release_detail.html'
download "https://downloads.mariadb.org/mariadb/+files/?release=$MARIA_DB_RELEASE&file_type=source" "$MARIA_DB_RELEASE_DETAIL"
MARIA_DB_DOWNLOAD_URL="https://downloads.mariadb.org/f/`grep '"filename"' $MARIA_DB_RELEASE_DETAIL | awk -F 'interstitial|">' '{ print $3 }'`"
MARIA_DB_ARCHIVE="mariadb-$MARIA_DB_VER.tar.gz"
download $MARIA_DB_DOWNLOAD_URL "$MARIA_DB_ARCHIVE"
echo "complete."

echo -n "Verifying integrity of MariaDB $MARIA_DB_VER package..."
verify_md5 "$MARIA_DB_ARCHIVE" `grep 'md5sum:' $MARIA_DB_RELEASE_DETAIL | awk '{ print $2 }'`
echo "complete."
echo
