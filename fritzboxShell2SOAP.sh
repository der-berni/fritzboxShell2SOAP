#!/usr/bin/env sh

_SCRIPT_="$0"

FB_IP="192.168.178.1"
FB_USER="admin"
FB_PASS="PASSWORD"
FB_SOAP_PORT="49000"

DEBUG=0
INTERACTIVE=0
NOCACHE=1
CACHEDIR="/tmp/${_SCRIPT_%.*}"
CACHEDIRCREATED=0

soap_nonce=
soap_realm=
soap_authstatus=
soap_response=

soap_serviceType=
soap_serviceId=
soap_controlURL=
soap_SCPDURL=

soap_ActionName=
soap_ServiceControl=

cache_Response=

soap_ArgumentsIn=
soap_ArgumentsOut=

__green() {
	if [ "${INTERACTIVE}${FBS2S_NO_COLOR}" = "1" ]; then
		printf '\033[1;31;32m'
	fi
	printf -- "%b" "$1"
	if [ "${INTERACTIVE}${FBS2S_NO_COLOR}" = "1" ]; then
		printf '\033[0m'
	fi
}

__red() {
	if [ "${INTERACTIVE}${FBS2S_NO_COLOR}" = "1" ]; then
		printf '\033[1;31;40m'
	fi
	printf -- "%b" "$1"
	if [ "${INTERACTIVE}${FBS2S_NO_COLOR}" = "1" ]; then
		printf '\033[0m'
	fi
}

__err() {
	if [ -z "$2" ]; then
		__red "$1" >&2
	else
		__red "$1='$2'" >&2
	fi
	printf "\n" >&2
	return 1
}

__debug() {
	if [ "${DEBUG}" = "1" ]; then
		if [ -z "$2" ]; then
			__log "$1" >&2
		else
			__log "$1: $2" >&2
		fi
		#printf "\n" >&2
	fi
}

__log() {
	if [ -z "$2" ]; then
		printf -- "%b" "$1"
	else
		printf -- "%b" "$1: $2"
	fi
	printf "\n"
}

__resetSOAP() {
	#soap_nonce=
	#soap_realm=
	soap_authstatus=
	soap_response=
	
	soap_serviceType=
	soap_serviceId=
	soap_controlURL=
	soap_SCPDURL=
	
	soap_ActionName=
	soap_ServiceControl=
}

__doChallenge() {
	local _content="$1"
	if [ -z "${_content}" ]; then __err "XML Content not defined!"; return 1; fi
	local _silent=$2
	if [ -z "${soap_controlURL}" ]; then __err "ServiceControl (controlURL) not defined!"; return 1; fi
	if [ -z "${soap_serviceType}" ]; then __err "ServiceControl (serviceType) not defined!"; return 1; fi
	if [ -z "${soap_ActionName}" ]; then __err "ActionName not defined!"; return 1; fi
	
	#if [ -z "${_silent}" ]; then __log "Initial Client Request"; fi
	
	local _header="<s:Header><h:InitChallenge xmlns:h=\"http://soap-authentication.org/digest/2001/10/\" s:mustUnderstand=\"1\"><UserID>${FB_USER}</UserID></h:InitChallenge></s:Header>"
	_content="${_content/###HEADER###/${_header}}"
	#remove line breaks
	_content=$(echo -n "${_content}" | awk '{printf "%s",$0} END {print ""}')
	
	local _response=$(curl -s -k --anyauth -u "${FB_USER}:${FB_PASS}" "http://${FB_IP}:${FB_SOAP_PORT}${soap_controlURL}" -H "Content-Type: text/xml; charset=\"utf-8\"" -H "SOAPAction:${soap_serviceType}#${soap_ActionName}" -d "${_content}" | sed 's/></>\n</g')
	
	soap_nonce=$(echo -n "${_response}" | awk -F '[<>]' '/<Nonce>/{print $3}')
	soap_realm=$(echo -n "${_response}" | awk -F '[<>]' '/<Realm>/{print $3}')
	
	if [ -z "${_silent}" ]; then __debug "soap_nonce:${soap_nonce}:"; fi
	if [ -z "${_silent}" ]; then __debug "soap_realm:${soap_realm}:"; fi
	
	return 0
}

__doSOAPRequest() {
	local _content="$1"
	if [ -z "${_content}" ]; then __err "XML Content not defined!"; return 1; fi
	local _silent=$2
	if [ -z "${soap_controlURL}" ]; then __err "ServiceControl (controlURL) not defined!"; return 1; fi
	if [ -z "${soap_serviceType}" ]; then __err "ServiceControl (serviceType) not defined!"; return 1; fi
	if [ -z "${soap_ActionName}" ]; then __err "ActionName not defined!"; return 1; fi
	
	if [ -z "${soap_nonce}" ]; then
		__doChallenge "${_content}"
		local _ret="$?"
		if [ "${_ret}" != "0" ]; then
			return "${_ret}"
		fi
	fi
	
	if [ -z "${_silent}" ]; then __log "Do Client Request" "${soap_ActionName}"; fi
	
	local _secret="${FB_USER}:${soap_realm}:${FB_PASS}"
	local _secretmd5=$(echo -n "${_secret}" | md5sum -t | awk '{print substr($0,1,32)}')
	local _authmd5=$(echo -n "${_secretmd5}:${soap_nonce}" | md5sum -t | awk '{print substr($0,1,32)}')
	
	if [ -z "${_silent}" ]; then __debug "soap_nonce" "${soap_nonce}:"; fi
	if [ -z "${_silent}" ]; then __debug "secret" "${_secret/${FB_PASS}/*****}:"; fi
	if [ -z "${_silent}" ]; then __debug "secretmd5" "${_secretmd5}:"; fi
	if [ -z "${_silent}" ]; then __debug "authmd5" "${_authmd5}:"; fi
	
	local _header="<s:Header><h:ClientAuth xmlns:h=\"http://soap-authentication.org/digest/2001/10/\" s:mustUnderstand=\"1\"><Nonce>${soap_nonce}</Nonce><Auth>${_authmd5}</Auth><UserID>${FB_USER}</UserID><Realm>${soap_realm}</Realm></h:ClientAuth></s:Header>"
	_content="${_content/###HEADER###/${_header}}"
	#remove line breaks
	_content=$(echo -n "${_content}" | awk '{printf "%s",$0} END {print ""}')
	
	soap_response=$(curl -s -k --anyauth -u "${FB_USER}:${FB_PASS}" "http://${FB_IP}:${FB_SOAP_PORT}${soap_controlURL}" -H "Content-Type: text/xml; charset=\"utf-8\"" -H "SOAPAction:${soap_serviceType}#${soap_ActionName}" -d "${_content}" | sed 's/></>\n</g')
	soap_authstatus=$(echo -n "${soap_response}" | awk -F '[<>]' '/<Status>/{print $3}')
	soap_nonce=$(echo -n "${soap_response}" | awk -F '[<>]' '/<Nonce>/{print $3}')
	soap_realm=$(echo -n "${soap_response}" | awk -F '[<>]' '/<Realm>/{print $3}')
	
	if [ "${soap_authstatus}" = "Authenticated" ]; then
		if [ -z "${_silent}" ]; then __log "$(__green "Request succeeded!")"; fi
	else
		__log "$(__red "Request failed!")" "$(echo -n "${soap_response}" | awk -F '[<>]' '/<errorDescription>/{print $3}')"
		return 1
	fi
	
	return 0
}

__getServiceList() {
	local _silent=$1
	
	if [ -z "${soap_SCPDURL}" ]; then soap_SCPDURL="/tr64desc.xml"; fi
	if [ -z "${_column}" ]; then _column="controlURL"; fi
	
	if [ "${NOCACHE}" = "1" ];then
		cache_Response=$(wget -qO- "http://${FB_IP}:${FB_SOAP_PORT}${soap_SCPDURL}" | sed 's/></>\n</g')
	else
		if [ ! -e "${CACHEDIR}${soap_SCPDURL}" ];then
			wget -q "http://${FB_IP}:${FB_SOAP_PORT}${soap_SCPDURL}" -O "${CACHEDIR}${soap_SCPDURL}" 2>/dev/null
		fi
		cache_Response=$(cat "${CACHEDIR}${soap_SCPDURL}" 2>/dev/null | sed 's/></>\n</g')
	fi
	
	if [ -z "${cache_Response}" ];then __err "Failed to requesting ${soap_SCPDURL}!"; return 1; fi
	
	if [ -z "${_silent}" -o "${_silent}" = "0" ]; then
		if [ -z "${soap_ServiceControl}" ]; then
			echo -n "${cache_Response}" | awk -F '[<>]' '/'"${_column}"'/{if($3!=""){print $3} }'
		else
			echo -n "${cache_Response}" | awk -F '[<>]' '{if($2=="controlURL" && $3=="/upnp/control/'${soap_ServiceControl}'"){found=1};if(found==1 && $2=="SCPDURL"){SCPDURL=$3;exit}}END{print SCPDURL}'
		fi
	fi
}

__showServiceList() {
	local _silent=$1
	
	if [ -z "${soap_SCPDURL}" ]; then soap_SCPDURL="/tr64desc.xml"; fi
	if [ -z "${_silent}" ]; then __debug "soap_SCPDURL" "${soap_SCPDURL}"; fi
	
	if [ -z "${_silent}" ]; then __log "Requesting" "$(__green ${soap_SCPDURL})"; fi
	
	local _servicelist=$(__getServiceList | sed 's/\/upnp\/control\///g' )
	local _ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	if [ -z "${_silent}" ]; then __log $(__green "ServiceControl"); fi
	if [ -z "${_silent}" ]; then __log "${_servicelist}"; fi
}

__showActionList() {
	local _silent=$1
	
	if [ -z "${soap_ServiceControl}" ]; then __err "ServiceControl required!"; return 1; fi
	if [ -z "${_silent}" ]; then __debug "soap_ServiceControl" "${soap_ServiceControl}"; fi
	
	soap_SCPDURL=$(__getServiceList)
	local _ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	__getServiceList 1
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	local _actionlist=$(echo -n "${cache_Response}" | awk '/actionList/,/\/actionList/' | awk '/action/,/\/name/{if ($0 ~ /name/) {str=$0;sub("<name>","",str);sub("<\/name>","",str);print str}}')
	if [ -z "${_silent}" ]; then __log $(__green "ActionName"); fi
	
	if [ -z "${_silent}" ]; then __log "${_actionlist}"; fi
	
	return 0
}

__showArguments() {
	local _silent=$1
	
	if [ -z "${soap_ServiceControl}" ]; then __err "ServiceControl required!"; return 1; fi
	if [ -z "${soap_ActionName}" ]; then __err "ActionName required!"; return 1; fi
	if [ -z "${_silent}" ]; then __debug "soap_ServiceControl" "${soap_ServiceControl}"; fi
	if [ -z "${_silent}" ]; then __debug "soap_ActionName" "${soap_ActionName}"; fi
	
	soap_SCPDURL=$(__getServiceList)
	local _ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	__getServiceList 1
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	if [ -z "${_silent}" ]; then __log "Parsing Arguments"; fi
	local _argumentlist=$(echo -n "${cache_Response}" | awk '/action/,/\/action/{if ($0 ~ /<name>'${soap_ActionName}'/){found=1;next}; if (found==1) {if($0 ~ /name/){str=$0;sub("<name>","",str);sub("<\/name>","",str)};{if($0 ~ /direction/){str2=$0;sub("<direction>","",str2);sub("<\/direction>","",str2); print str2 ":" str};if($0 ~ /\/action/){exit} } } }')
	
	if [ -z "${_silent}" ]; then __log "Agruments for Action" "$(__green ${soap_ActionName})"; fi
	if [ -z "${_silent}" ]; then __log "$(__green direction):$(__green argument)"; fi
	if [ -z "${_silent}" ]; then __log "${_argumentlist}"; fi
	
	return 0
}

__initServiceParameters() {
	local _silent=$1
	
	if [ -z "${soap_ServiceControl}" ]; then __err "ServiceControl required!"; return 1; fi
	
	__getServiceList 1
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	if [ -z "${cache_Response}" ];then __err "initServiceParameters" "Failed to requesting /tr64desc.xml!"; __log "${cache_Response}"; return 1; fi
	
	local _serviceargs=$(echo -n "${cache_Response}" | awk '/serviceList/,/\/serviceList/' | awk -F '[<>]' '{if($2=="serviceType"){serviceType=$0};if($2=="serviceId"){serviceId=$0};if($2=="controlURL" && $3=="/upnp/control/'${soap_ServiceControl}'"){found=1;controlURL=$0};if($2=="eventSubURL"){eventSubURL=$0};if($2=="SCPDURL" && found==1){print serviceType"\n"serviceId"\n"controlURL"\n"eventSubURL"\n"$0;exit}}')
	
	if [ -z "${_silent}" ]; then __log "Parsing ServiceParameters"; fi
	
	for _line in ${_serviceargs}
	do
		local _key=$(echo -n "${_line}" | awk -F '[<>]' '{print $2}')
		local _val=$(echo -n "${_line}" | awk -F '[<>]' '{print $3}')
		
		__parse_argument "soap_${_key}" "${_val}"
	done
	return 0
}

__initArguments() {
	local _silent=$1
	
	if [ -z "${soap_ServiceControl}" ]; then __err "ServiceControl required!"; return 1; fi
	if [ -z "${soap_ActionName}" ]; then __err "ActionName required!"; return 1; fi
	if [ -z "${_silent}" ]; then __debug "soap_ServiceControl" "${soap_ServiceControl}"; fi
	if [ -z "${_silent}" ]; then __debug "soap_ActionName" "${soap_ActionName}"; fi
	
	__getServiceList 1
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	if [ -z "${_silent}" ]; then __log "Parsing Arguments"; fi
	local _arguments=$(echo -n "${cache_Response}" | awk '/action/,/\/action/{if ($0 ~ /<name>'${soap_ActionName}'/){found=1;next}; if (found==1) {if($0 ~ /name/){str=$0;sub("<name>","",str);sub("<\/name>","",str)};{if($0 ~ /direction/){str2=$0;sub("<direction>","",str2);sub("<\/direction>","",str2); print str ":" str2};if($0 ~ /\/action/){exit} } } }')
	
	for _line in ${_arguments}
	do
		local _key=$(echo -n "${_line}" | awk -F ':' '{print $1}')
		local _direction=$(echo -n "${_line}" | awk -F ':' '{print $2}')
		
		if [ "${_direction}" = "in" ]; then
			if ! __contains "${soap_ArgumentsIn}" "${_key}"; then
				soap_ArgumentsIn="${soap_ArgumentsIn} ${_key}"
			fi
			
			local _tmpvar=$(eval echo "\$${_key}")
			if [ -z ${_tmpvar} ]; then __err "${_key} required!"; return 1; fi
		else
			if ! __contains "${soap_ArgumentsOut}" "${_key}"; then
				soap_ArgumentsOut="${soap_ArgumentsOut} ${_key}"
			fi
		fi
	done
	
	soap_ArgumentsIn=$(echo -n "${soap_ArgumentsIn}" | sed 's/  */ /g')
	soap_ArgumentsOut=$(echo -n "${soap_ArgumentsOut}" | sed 's/  */ /g')
	
	if [ -z "${_silent}" ]; then __debug "Arguments required" "${soap_ArgumentsIn}"; fi
	if [ -z "${_silent}" ]; then __debug "Arguments Output" "${soap_ArgumentsOut}"; fi
	return 0
}

__doAction() {
	local _silent=$1
	if [ -z "${_silent}" ]; then _silent=1; fi
	
	if [ -z "${soap_ServiceControl}" ]; then __err "ServiceControl required!"; return 1; fi
	if [ -z "${soap_ActionName}" ]; then __err "ActionName required!"; return 1; fi
	__debug "soap_ServiceControl" "${soap_ServiceControl}"
	__debug "soap_ActionName" "${soap_ActionName}"
	
	local _ret=
	local _val
	
	__initServiceParameters ${_silent}
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	__initArguments ${_silent}
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	local _arguments=
	local _content="<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">###HEADER###<s:Body><u:${soap_ActionName} xmlns:u=\"${soap_serviceType}\">###ARGUMENTS###</u:${soap_ActionName}></s:Body></s:Envelope>"
	
	for _arg in ${soap_ArgumentsIn}
	do
		local _tmpvar=$(eval echo "\$${_arg}")
		_arguments="${_arguments}<${_arg}>${_tmpvar}</${_arg}>"
	done
	
	_content="${_content/###ARGUMENTS###/${_arguments}}"
	
	__doSOAPRequest "${_content}" ${_silent}
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	for _key in ${soap_ArgumentsOut}
	do
		_val=$(echo -n "${soap_response}" | awk -F '[<>]' '/'${_key}'/{print $3}')
		if [ ! -z "${_val}" ]; then
			__log "${_key}" "${_val}" 
			__parse_argument "${_key}" "\"${_val}\""
		fi
	done
	
	return 0
}

__getSpecificPortMappingEntry() {
	local _silent=$1
	
	__resetSOAP
	if [ -z "${NewExternalPort}" ]; then __err "NewExternalPort required!"; return 1; fi
	if [ -z "${NewRemoteHost}" ]; then NewRemoteHost="0.0.0.0"; fi
	if [ -z "${NewProtocol}" ]; then NewProtocol="TCP"; fi
	
	soap_ServiceControl="wanipconnection1"
	soap_ActionName="GetSpecificPortMappingEntry"
	
	__doAction ${_silent}
	local _ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	return 0
}

__addPortMapping() {
	local _silent=$1
	__resetSOAP
	
	if [ -z "${NewExternalPort}" ]; then __err "NewExternalPort required!"; return 1; fi
	if [ -z "${NewRemoteHost}" ]; then NewRemoteHost="0.0.0.0"; fi
	if [ -z "${NewProtocol}" ]; then NewProtocol="TCP"; fi
	
	local _ret=
	local _forceNewEnabled="${NewEnabled}"
	if [ -z "${NewInternalPort}" -o -z "${NewInternalClient}" -o -z "${NewEnabled}" -o -z "${NewPortMappingDescription}" -o -z "${NewLeaseDuration}" ]; then 
		__getSpecificPortMappingEntry 1
		_ret="$?"
		if [ "${_ret}" != "0" ]; then
			return "${_ret}"
		fi
		
		if [ "${NewEnabled}" = "0" ]; then
			NewEnabled=1
		else
			NewEnabled=0
		fi
	fi
	if [ ! -z "${_forceNewEnabled}" ]; then
		NewEnabled="${_forceNewEnabled}"
	fi
	
	soap_ServiceControl="wanipconnection1"
	soap_ActionName="AddPortMapping"
	
	__doAction ${_silent}
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	return 0
}

__uploadSSLCert() {
	local _silent=1
	__resetSOAP
	
	if [ -z "${SSLCertFile}" ]; then __err "SSLCertFile required!"; return 1; fi
	
	local _ret=
	
	soap_ServiceControl="deviceconfig"
	soap_ActionName="X_AVM-DE_CreateUrlSID"
	
	__doAction 1
	_ret="$?"
	if [ "${_ret}" != "0" ]; then
		return "${_ret}"
	fi
	
	if [ -z "${NewX_AVM-DE_UrlSID}" ]; then __err "Failed to generate UrlSID!"; return 1; fi
	if [ ! -z $(cat "${SSLCertFile}" | grep -q "BEGIN CERTIFICATE") ]; then __err "SSLCertFile is not valid!"; return 1; fi
	if [ ! -z $(cat "${SSLCertFile}" | grep -q "BEGIN PRIVATE KEY") ]; then __err "SSLCertFile is not valid!"; return 1; fi
	
	# temporary file
	local _tmpfile="$(mktemp -t XXXXXX)"
	chmod 600 ${_tmpfile}
	
	local _BOUNDARY="---------------------------"`date +%Y%m%d%H%M%S`
	printf -- "--${_BOUNDARY}\r\n" >> "${_tmpfile}"
	printf "Content-Disposition: form-data; name=\"sid\"\r\n\r\n${NewX_AVM-DE_UrlSID}\r\n" >> "${_tmpfile}"
	printf -- "--${_BOUNDARY}\r\n" >> "${_tmpfile}"
	printf "Content-Disposition: form-data; name=\"BoxCertPassword\"\r\n\r\n${CERTPASSWORD}\r\n" >> "${_tmpfile}"
	printf -- "--${_BOUNDARY}\r\n" >> "${_tmpfile}"
	printf "Content-Disposition: form-data; name=\"BoxCertImportFile\"; filename=\"BoxCert.pem\"\r\n" >> "${_tmpfile}"
	printf "Content-Type: application/octet-stream\r\n\r\n" >> "${_tmpfile}"
	cat "${SSLCertFile}" >> "${_tmpfile}"
	printf "\r\n" >> "${_tmpfile}"
	printf -- "--${_BOUNDARY}--" >> "${_tmpfile}"
	# upload the certificate to the box
	wget -q -O - "http://${FB_IP}/cgi-bin/firmwarecfg" --header="Content-type: multipart/form-data boundary=${_BOUNDARY}" --post-file "${_tmpfile}" | grep SSL

	# clean up
	rm -rf "${_tmpfile}" >/dev/null 2>&1

	return 0
}

__process() {
	local _CMD=
	
	while [ ${#} -gt 0 ]; do
		case "${1}" in

		--help | -h)
			__showhelp
			return
			;;
		--version | -v)
			__version
			return
			;;
		--debug)
			DEBUG=1
			;;
		--no-color)
			FBS2S_NO_COLOR=1
			;;
		--cache)
			NOCACHE=0
			;;
		-cachedir)
			CACHEDIR="$2"
			shift
			;;
		-fb-ip | -ip)
			FB_IP="$2"
			shift
			;;
		-fb-user | -u)
			FB_USER="$2"
			shift
			;;
		-fb-pass | -p)
			FB_PASS="$2"
			shift
			;;
		-fb-soap-port | -sp)
			FB_SOAP_PORT="$2"
			shift
			;;
		--GetSpecificPortMappingEntry)
			_CMD="GetSpecificPortMappingEntry"
			;;
		--AddPortMapping)
			_CMD="AddPortMapping"
			;;
		--ShowServiceList | -ssl)
			_CMD="ShowServiceList"
			;;
		--ShowActionList | -sal)
			_CMD="ShowActionList"
			;;
		--ShowArguments | -sa)
			_CMD="ShowArguments"
			;;
		--Action | -a)
			_CMD="Action"
			;;
		-ServiceControl)
			soap_ServiceControl="$2"
			shift
			;;
		-ActionName)
			soap_ActionName="$2"
			shift
			;;
		--UploadSSLCert)
			_CMD="UploadSSLCert"
			;;
		-SSLCertFile)
			SSLCertFile="$2"
			shift
			;;
		-CertPassword)
			CertPassword="$2"
			shift
			;;
		*)
			if __startswith "$1" "-New"; then
				__parse_argument "$1" "$2"
				shift
			else
				__err "Unknown parameter : $1"
				return 1
			fi
			;;
		esac

		shift 1
	done

	if [ -t 1 ]; then
	  INTERACTIVE="1"
	fi
	if [ "${_CMD}" != "" ]; then
		
		for _var in curl wget tr awk grep md5sum
		do
			if ! __command_exists "${_var}" ; then __err "Command not found: ${_var}"; __log "Pleace check dependencies!"; return 1; fi
		done
		
		if [ "${NOCACHE}" = "0" -a ! -e "${CACHEDIR}" ]; then
			mkdir -p "${CACHEDIR}"
			CACHEDIRCREATED=1
		fi
	fi
	
	if [ "${_CMD}" = "Action" ]; then
		__doAction
		return "$?"
	fi
	if [ "${_CMD}" = "ShowServiceList" ]; then
		soap_ServiceControl=
		__showServiceList
		return "$?"
	fi
	if [ "${_CMD}" = "ShowActionList" ]; then
		__showActionList
		return "$?"
	fi
	if [ "${_CMD}" = "ShowArguments" ]; then
		__showArguments
		return "$?"
	fi
	if [ "${_CMD}" = "GetSpecificPortMappingEntry" ]; then
		__getSpecificPortMappingEntry
		return "$?"
	fi
	if [ "${_CMD}" = "AddPortMapping" ]; then
		__addPortMapping
		return "$?"
	fi
	if [ "${_CMD}" = "UploadSSLCert" ]; then
		__uploadSSLCert
		return "$?"
	fi
}

__showhelp() {

__log "Usage: ${_SCRIPT_} command action arguments
example: ${_SCRIPT_} --debug --action --ServiceControl \"wanipconnSCPD\" --ActionName \"GetNATRSIPStatus\" --argument1 \"value1\"
example: ${_SCRIPT_} --ShowArguments GetSpecificPortMappingEntry

Commands:
  --help, -h                        Show this help message.
  --version, -v                     Show version info.
  --debug                           Output debug info.
  --no-color                        Do not output color text.

  --cache                           Do not cache files. By default: ${NOCACHE}
  -cachedir                         Set cache Directory for temp files. By default: ${CACHEDIR}

  -fb-ip, -ip                       Fritzbox IP-Address/Hostname. By Default: 192.168.178.1
  -fb-user, -u                      Fritzbox User. By Default: admin
  -fb-pass, -p                      Fritzbox Password required
  -fb-soap-port, -sp                By Default: 49000

Actions:
  --ShowServiceList, -ssl           Get list of Services

  --ShowActionList, -sal            Get list of Actions for Service
Arguments:
    -ServiceControl                 See ShowServiceList

  --ShowArguments, -sa              Get list of Arguments for action
Arguments:
    -ServiceControl                 See ShowServiceList
    -ActionName                     See ShowActionList

  --Action, -a                      Do Action
Arguments:
    -ServiceControl                 See ShowServiceList
    -ActionName                     See ShowActionList
    -Arguments as KeyValuePair      See ShowArguments, direction <in> is required

ShortCuts
  --GetSpecificPortMappingEntry     List specific Port mapping
Arguments:
    -NewExternalPort                required

  --AddPortMapping                  Add or Update Port mapping
Arguments:
    -NewExternalPort                required
    -NewInternalPort                only if Port mapping not exists
    -NewInternalClient              only if Port mapping not exists
    -NewEnabled                     only if Port mapping not exists | if Empty and Port mapping exists it will toggle 
    -NewPortMappingDescription      only if Port mapping not exists
    -NewLeaseDuration               only if Port mapping not exists

  --UploadSSLCert                   List specific Port mapping
Arguments:
    -SSLCertFile                    required (Private and Certificate)
	-CertPassword

  "
}

__parse_argument() {
	local _key="$1"
	local _value="$2"
	eval "${_key/-/}"="${_value}"
	__debug "Creating variable" "${_key/-/}=${_value}"
}

__version() {
	__log "${_SCRIPT_}"
	__log "v0.1.0"
}

__upper_case() {
	tr 'a-z' 'A-Z'
}

__lower_case() {
	tr 'A-Z' 'a-z'
}

__startswith() {
	_str="$1"
	_sub="$2"
	echo "${_str}" | grep "^${_sub}" >/dev/null 2>&1
}

__endswith() {
	_str="$1"
	_sub="$2"
	echo "${_str}" | grep -- "${_sub}\$" >/dev/null 2>&1
}

__contains() {
	_str="$1"
	_sub="$2"
	echo "${_str}" | grep -- "${_sub}" >/dev/null 2>&1
}

__command_exists() {
	type "$1" &> /dev/null;
}

__clearcache() {
	if [ "${NOCACHE}" = "1" ]; then
		if [ -e "${CACHEDIR}" -a "${CACHEDIRCREATED}" = "1" ]; then
			rm -rf "${CACHEDIR}"
		fi
	fi
}

__main() {
	[ -z "$1" ] && __showhelp && return
	__process "$@"
	_ret="$?"
	__clearcache()
	exit "${_ret}"
}

__main "$@"
