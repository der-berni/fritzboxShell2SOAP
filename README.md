# fritzboxShell2SOAP
Communicate with your Fritzbox from your shell via its SOAP api (TR-064 specification)

The script can be used to perform all actions supported by the specification.

API Specification:
https://avm.de/service/schnittstellen/

Script can output:
- Get list of Services
- Get list of Actions for Service
- Get list of Arguments for Action

Some Shortcuts:
- Reboot Fritzbox
- List specific Port mapping
- Add or Update Port mapping
- Upload SSL Certificate

# Change Log

**v0.1.2**
- added ShortCut reboot
- added the possibility of a config file

## Usage
```
Usage: fritzboxShell2SOAP.sh command action arguments
example: fritzboxShell2SOAP.sh --debug --action --ServiceControl "wanipconnSCPD" --ActionName "GetNATRSIPStatus" --argument1 "value1"
example: fritzboxShell2SOAP.sh --ShowArguments GetSpecificPortMappingEntry

# Commands #
  --help, -h                        Show this help message.
  --version, -v                     Show version info.
  --debug                           Output debug info.
  --no-color                        Do not output color text.

  --cache                           Cache files. By default: 1
  -cachedir                         Set cache Directory for temp files. By default: /tmp/fritzboxShell2SOAP

  -fb-ip, -ip                       Fritzbox IP-Address/Hostname. By Default: 192.168.178.1
  -fb-user, -u                      Fritzbox User. By Default: admin
  -fb-pass, -p                      Fritzbox Password required
  -fb-soap-port, -sp                By Default: 49000
  
  -f                                Config file. By default: fritzboxShell2SOAP.conf
  --CreateConfig | -cc              Write config file.



# Actions #
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



# ShortCuts #
  --reboot                          Reboot Fritzbox

  --GetSpecificPortMappingEntry     List specific Port mapping
    Arguments:
    -NewExternalPort                required

  --AddPortMapping                  Add or Update Port mapping
    Arguments:
    -NewExternalPort                required
    -NewInternalPort                only if Port mapping not exists
    -NewInternalClient              only if Port mapping not exists
    -NewEnabled                     only if Port mapping not exists | if empty and port mapping exists, the port will be toogled
    -NewPortMappingDescription      only if Port mapping not exists
    -NewLeaseDuration               only if Port mapping not exists

  --UploadSSLCert                   Upload SSL Certificate
    Arguments:
    -SSLCertFile                    required (Private and Certificate)
	-CertPassword
```

#### Dependencies
- curl
- wget
- tr
- awk
- grep
- md5sum

