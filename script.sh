#!/bin/bash
# Данный скрипт выполняет бекап директории, в которой он находится.
# 31 числа годовой, по воскресеньям недельный и тд.
#
# Нужно указать путь для бекапа -b и файл конфигурации -c.
#
# О файле конфигурации:
# - он в формате yaml
# - можно через него включать или выключать функцию удаления старых бекапов
# - можно выбирать архиватор. Но если не tar, то скрипт сообщит.
#
# О логировании:
# - используется systemd-cat для записи лога
#
#set -eo pipefail
#set -x

#логирование с помощью systemd-cat, перенаправление FD
exec > >(tee >(systemd-cat -t ${BASH_SOURCE##*/} -p 5))
exec 2> >(tee >(systemd-cat -t ${BASH_SOURCE##*/} -p 3))

#проверить наличие yq
check_yq() {
if which yq &>/dev/null; then
	echo "Continuing with yaml config"
else echo "No yq installed, you can't use config. Aborting" >&2; sleep 1; exit 1
fi
}

while getopts "b:c:" opt ; do
	case "$opt" in
		c) CONFIG_PATH="${OPTARG}"
			;;
		b) BACKUP_PATH="${OPTARG}"
			;;
		*) echo "Arguments are b|c"; sleep 1; exit 1
			;;
	esac
done

#проверка конфига
check_config() {
[ -z $CONFIG_PATH ] || [ ! -f ${CONFIG_PATH} ] 
	case "$?" in 
		0) echo "No config, quitting" >&2; sleep 1; exit 1
		;;
		1) echo "Checking config"
		;;
esac

	local check=$(yq < "${CONFIG_PATH}" &>/dev/null) 
	echo $check
	case $check in
		0) echo "Config is fine, moving on"
			;;
		1|2) echo "Config is broken, exiting" >&2; sleep 1; exit 1
			;;
	esac
}

#парсим конфиг
parse_config() {

ARCHIVATOR="$(yq < "${CONFIG_PATH}" | jq '.script_config.archivator')"
AUTO_DELETE="$(yq < "${CONFIG_PATH}" | jq '.script_config.auto_clean_backup')"
	case "${ARCHIVATOR}" in
	       '"tar"') echo "You choose TAR, good choice"
			;;
		*) echo "${ARCHIVATOR} is not supported" >&2; sleep 1; exit 1
			;;

	esac

			
}

#запускаем функции проверки конфига и парсинг
check_config
[ ! -z "${CONFIG_PATH}" ] && parse_config

#функция создания директории и поддиректорий
mk_bkp_dir() {
mkdir -p "${BACKUP_PATH}"/{yearly,monthly,weekly,daily}
case $? in
	0) echo "Backup dir created"
		;;
	1) echo "Failed to create backup dir" >&2; sleep 1;
		;;
esac

}

#проверка существования директории и создание директории
[ -d "$BACKUP_PATH" ]
case "$?" in
	0) echo "Backup dir exists";
		;;
	1) mk_bkp_dir
		;;
esac

#проверка, установлен ли архиватор
ARCHIVATOR=tar

if which "${ARCHIVATOR}" &>/dev/null; then 
	echo "Archivator is ${ARCHIVATOR}"
else 
	echo "Archivator ${ARCHIVATOR} not found"
       	exit 1
fi

#создание yearly, monthly, weekly бекапа
CURRENT_DATE=$(date +%d)
CURRENT_DAY=$(env LC_TIME=en_US.UTF-8 date +%a) 

YEARLY="${BACKUP_PATH}"/yearly/$(date +%Y_%m_%d)_yearly_"${PWD##*/}".tar
MONTHLY="${BACKUP_PATH}"/monthly/$(date +%Y_%m_%d)_monthly_"${PWD##*/}".tar
WEEKLY="${BACKUP_PATH}"/weekly/$(date +%Y_%m_%d)_weekly_"${PWD##*/}".tar
DAILY="${BACKUP_PATH}"/daily/$(date +%Y_%m_%d)_daily_"${PWD##*/}".tar

case ${CURRENT_DATE} in
	 #не класть в бекап сам скрипт и сам бекап
	"31") echo "Creating yearly backup"; 
		tar --exclude "${BASH_SOURCE##*/}" --exclude "${BACKUP_PATH}" -cvf ${YEARLY} "${PWD}"/ ||  
		echo "Yearly backup failed" >&2; sleep 1; 
		;;
	"01") echo "Creating monthly backup"; 
		tar --exclude "${BASH_SOURCE##*/}" --exclude "${BACKUP_PATH}" -cvf ${MONTHLY} "${PWD}"/ ||  
		echo "Monthly backup failed" >&2; sleep 1;
		;;
	"sun") echo "Creating weekly backup"; 
		tar  --exclude "${BASH_SOURCE##*/}" --exclude "${BACKUP_PATH}" -cvf ${WEEKLY} "${PWD}"/ ||  
		echo "Weekly backup failed" >&2; sleep 1;
		;;
	*) echo "Creating daily backup"; 
		tar  --exclude "${BASH_SOURCE##*/}" --exclude "${BACKUP_PATH}" -cvf ${DAILY} "${PWD}"/ ||  
		echo "Daily backup failed" >&2; sleep 1;
		;;
esac


echo "Backup finished"
#функция очистки бекапов
delete_old_bkps() {

find "${BACKUP_PATH}"/daily/ -type f -printf "\n%Ad\t%p" | 
	awk 'BEGIN {FS = "\t"} {NR > 7} {print $2}' | 
	xargs -I {} echo rm -v "{}" || echo "Deleting failed" >&2; sleep 1;
find "${BACKUP_PATH}"/weekly/ -type f -printf "\n%Ad\t%p" | 
	awk 'BEGIN {FS = "\t"} {NR > 4} {print $2}' |
	xargs -I {} echo rm -v "{}" || echo "Deleting failed" >&2; sleep 1;
find "${BACKUP_PATH}"/monthly/ -type f -printf "\n%Ad\t%p" | 
	awk 'BEGIN {FS = "\t"} {NR > 4} {print $2}' |
	xargs -I {} echo rm -v "{}" || echo "Deleting failed" >&2; sleep 1;
find "${BACKUP_PATH}"/yearly/ -type f -printf "\n%Ad\t%p" |
	awk 'BEGIN {FS = "\t"} {NR > 2} {print $2}' |
	xargs -I {} echo rm -v "{}" || echo "Deleting failed" >&2; sleep 1;
}

#проверка, что указано в конфиге насчет автоудаления
case "$AUTO_DELETE" in
		"true") delete_old_bkps
			;;
		"false") echo "Keeping old backups"
			;;
		*) echo "Check your yaml options"
	esac
	exit 0
