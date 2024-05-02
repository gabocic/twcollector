#!/usr/bin/env bash

# Load configuration
parent_path=$(dirname "${BASH_SOURCE[0]}")
. $parent_path/config $parent_path

function log() {
    case $1 in
        ([eE][rR][rR][oO][rR]):
        level="ERROR"
        ;;
        ([iI][nN][fF][oO]):
        level="INFO"
        ;;
        ([wW][aA][rR][nN]):
        level="WARN"
        ;;
    esac    
    echo `date +'%Y-%m-%d-%H:%M:%S'` "[$level]" $2 | tee -a $log_file
}

function tool_exists() {
    toolpath=""
    local istoolinst=`which $1 > /dev/null 2>&1; echo $?`
    if [ $istoolinst -ne 0 ]
    then
        log error "$1 is not installed or is not on PATH. Exiting.."
        exit 1
    else
        log info "$1 is present on the system"
        toolpath=`which $1`
    fi
}

function banner() {
    echo "============================================" 
    echo "===   Slow query and Stats collection    ==="
    echo "============================================"
    echo ""
}

function request_db_params() {
    default_db_host="127.0.0.1"
    default_db_port=3306
    
    read -p "Please provide the Database user: " db_user
    read -sp "Please provide the Database password: " db_pass
    echo ""
    read -p "If connecting through socket, please specify the path: " db_sock
    if [ -z $db_sock ]
    then
        read -p "Please provide the Database host [$default_db_host]: " db_host
        db_host=${db_host:-$default_db_host}
        read -p "Please provide the Database port [$default_db_port]: " db_port
        db_port=${db_port:-$default_db_port}
    fi
    read -p "Please specify the database name, in case we need it: " defaultdb
}


function test_db_connection() {
    dbcli="$dbcli -A --connect-timeout 1"
    if [ -z $db_sock ]
    then
        local connerror="Unable to connect to the database server in $db_host, on port $db_port, with user $db_user"
        dbcli="$dbcli -h $db_host -u $db_user -p$db_pass -P$db_port"
    else
        local connerror="Unable to connect to the database server on socket $db_sock, with user $db_user"
        dbcli="$dbcli -S $db_sock -u $db_user -p$db_pass"
    fi

    $dbcli -e"select now()" > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "$connerror"
        exit 1
    else
        log info "Successfully connected to database server"
        dbclisil="$dbcli -NBs"
    fi
}

function retrieve_mysql_param() {
    #p1: parameter name
    #p2: return variable
    #p3: can fail
    
    local __resultvar=$2
    # Sanitize value
    local dbparam=`echo $1 | sed -e "s/[[',;]]\+//g" -e "s/[[:blank:]]\+//g"`
    dbparamval=`$dbclisil -e "select @@${dbparam}" 2>/dev/null`
    if [ $? -ne 0 ]
    then
        if [ $3 -eq 0 ]
        then
            log error "Failed trying to retrieve parameter '$dbparam'"
            exit 1
        else
            log warn "Failed trying to retrieve parameter '$dbparam'"
            dbparamval="NULL"
        fi
    fi
    eval $__resultvar="'$dbparamval'"
}

function execute_query() {
    #p1: database
    #p2: return variable
    #p3: can fail
    #p4: query
    
    local __resultvar=$2
    queryres=`$dbclisil $1 -e "$4" 2>/dev/null`
    if [ $? -ne 0 ]
    then
        if [ $3 -eq 0 ]
        then
            log error "Failed trying to execute query ${2}"
            exit 1
        else
            log warn "Failed trying to execute query ${2}"
            queryres="NULL"
        fi
    fi
    eval $__resultvar="'$queryres'"
}

function save_var_to_file() {
    #p1: parameter name
    #p2: parameter value
    #p3: file name
    echo \"$1\",\"$2\" >> $3
}

function init_dirs() {
    mkdir -p $output_dir > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log error "I was not able to create the directories I need to collect information. 
            Please review permissions on '$output_dir' or change the path in ./config"
        exit 1
    fi
    rm -fv $general_info_file > /dev/null 2>&1
    rm -fv $optimizer_switch_file > /dev/null 2>&1
    rm -fv $stats_conf_file > /dev/null 2>&1
    rm -fv $query_digest_file > /dev/null 2>&1
    rm -fv $output_dir/$sql_commands_file > /dev/null 2>&1
    rm -fv $table_list_file > /dev/null 2>&1
    rm -fv $schema_info_file > /dev/null 2>&1
    rm -fv $output_dir/$explain_stmt_file > /dev/null 2>&1
    rm -fv $output_dir/$mdb_costs_query_script > /dev/null 2>&1
    rm -fv $output_dir/*.txt > /dev/null 2>&1
    rm -fv $output_dir/*_querycollector.tar.gz > /dev/null 2>&1
}

function run_db_script() {
    #p1: script
    #p2: output file
    #p3: script description for logging purposes
    #p4: verbose? 

    if [ $4 -eq 1 ]
    then
        local mysqlcli="$dbcli -vvv"
    else
        local mysqlcli="$dbcli"
    fi
    $mysqlcli -s -e "source $1" > $2 2>/dev/null
    if [ $? -ne 0 ]
    then
        log error "Something went wrong when executing $3"
        exit 1
    fi
}

function output_sanitizer() {
    # Declare associative array (BASH version > 4.0)
    declare -A valuesaa

    # Modify IFS to not use :space: as separator
    IFS=$'\n'

    # Iterate over all query explain output files
    for file in $(ls -1 $output_dir/*.txt | grep '[A-Z,0-9]')
    do

        # For each file, iterate over query values found
        for value in $(grep -o -P "'([^']*)'" $file | sort -u; grep -e "attached_condition" -e "Message:" -e "expanded_query" -e "original_condition" -e "resulting_condition" -e "attached" -e "constant_condition_in_bnl" $file  | awk -F ":" '{print $2}' | sed  's/"//' | sed 's/"$//'| grep -o -P '"([^"]*)"' | sort -u)
        do
            valuecode=""

            # Remove single-quotes
            value=${value:1:-1}

            # If value was not added before
            if [ ! ${valuesaa[$value]+_} ]
            then
                if [[ $value =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}.*$ ]]
                then
                    valuecode=date
                else
                    # Check for % at the begining
                    if [ "${value:0:1}" == "%" ]
                    then
                        valuecode="%"
                    fi

                    # Check for _ at the begining
                    if [ "${value:0:1}" == "_" ]
                    then
                        valuecode="_"
                    fi

                    matched=0
                    # Check if integer
                    echo "$value" | grep '^[0-9]*$' > /dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        valuecode=$valuecode"int"
                        matched=1
                    fi

                    # Check if decimal
                    echo "$value" | grep '^[0-9.,]*$' > /dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        valuecode=$valuecode"float"
                        matched=1
                    fi

                    # If not decimal or int, then alpha
                    if [ $matched -eq 0 ]
                    then
                        valuecode=$valuecode"alpha"    
                    fi

                    # Check if we have % in between
                    echo "${value:1:-1}" | grep '%' > /dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        valuecode=$valuecode"-perc"
                    fi

                    # Check if we have _ in between
                    echo "${value:1:-1}" | grep '_' > /dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        valuecode=$valuecode"-unders"
                    fi

                    # Check for % at the end
                    echo "${value:0-1}" | grep '%' > /dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        valuecode=$valuecode"%"
                    fi

                    # Check for _ at the end
                    echo "${value:0-1}" | grep '_' > /dev/null 2>&1
                    if [ $? -eq 0 ]
                    then
                        valuecode=$valuecode"_"
                    fi
                fi
                valuesaa+=([$value]=$valuecode)
            fi
        done
    done

    # Iterate over all query explain output files
    for file in $(ls -1 $output_dir/*.txt | grep '[A-Z,0-9]')
    do
        for key in "${!valuesaa[@]}"
        do
            sed -i "s|$key|${valuesaa[$key]}|g" $file
        done
    done
}

function token_request() {

    function register_account() {
        read -p "Please write your first name: " first_name
        read -p "Please write your last name: " last_name
        read -p "Please provide an active email: " email
        read -sp "Please provide a password. This will be required in case you want to retrieve the token again: " password_1
        read -sp "Repeat the password one more time: " password_2
        
        while [ "$password_1" != "$password_2" ]
        do
          log warn "Passwords don't match"
          read -p "Please provide a password. This will be required in case you want to retrieve the token again: " password_1
          read -p "Repeat the email one more time: " password_2
        done

        regdatajs='{
        "email":"'$email'",
        "password":"'$password_1'",
        "first_name":"'$first_name'",
        "last_name":"'$last_name'"
        }'

        # Sign up
        curl -X POST -H 'Content-Type: application/json' -d "$regdatajs" 'https://tuningwizard.query-optimization.com/api/accounts/signup/' > /dev/null 2>&1
        log info "Check your email and verify your account. Then press enter.."
        read

        # Login and get your token
        tokenresp=`curl -X POST -H 'Content-Type: application/json' -d "$regdatajs" 'https://tuningwizard.query-optimization.com/api/accounts/login/'`
        echo $?
        auth_token=`echo $tokenresp  | awk -F '"' '{print $4}'`
    }
    
    ## Main
    read -p "You need a Tuning Wizard API token to authenticate. If you already have one, please paste it here. Otherwise, hit enter to request one:" auth_token
    echo ""
    if [ -z $auth_token ]
    then
        register_account
    fi
}

function main() {

    # Create collection directories and remove any files
    init_dirs
    log info "======= Starting collection process ========"

    # Check that the MySQL client is installed
    tool_exists mysql
    dbcli=$toolpath

    # Check that Perl is installed  
    tool_exists perl

    # Ask for the database server connection details"
    request_db_params

    # Test database connection
    test_db_connection

    # Retrieve relevant server configuration
    retrieve_mysql_param "version" dbparam_version 0
    save_var_to_file version $dbparam_version $general_info_file

    retrieve_mysql_param "innodb_version" dbparam_idb_version 0
    save_var_to_file idb_version $dbparam_idb_version $general_info_file
    major_version=`echo $dbparam_idb_version | awk -F "." '{print $1"."$2}'`

    # Are we working with MariaDB?
    ismdb=`echo "$dbparam_version" | grep -i 'mariadb' | wc -l`

    # Check slow query log configuration
    retrieve_mysql_param "slow_query_log" dbparam_slowquerylog
    if [ "$dbparam_slowquerylog" == "1" ]
    then
        log info "Slow query log is enabled"
    else
        log warn "Slow query log is disabled"
    fi
    
    retrieve_mysql_param "long_query_time" dbparam_longquerytime 0
    log info "Long query time set to $dbparam_longquerytime seconds"
    save_var_to_file long_query_time $dbparam_longquerytime $general_info_file

    retrieve_mysql_param "min_examined_row_limit" dbparam_minexaminedrowlimit 0
    log info "Minimum rows read to be included in the slow query log: $dbparam_minexaminedrowlimit"
    
    retrieve_mysql_param "log_output" dbparam_logoutput 0
    log info "Slow query log output is set to $dbparam_logoutput"

    # Retrieve path for slow query log
    retrieve_mysql_param "slow_query_log_file" dbparam_slowquerylogfile 0
    log info "Slow query log file path: $dbparam_slowquerylogfile"

    # Check access to slow query log file
    ls $dbparam_slowquerylogfile > /dev/null 2>&1
    if [ $? -ne 0 ]
    then
        log warn "I can't access the slow query log in '$dbparam_slowquerylogfile'"
        read -p "Please specify the location of the slow query log: " dbparam_slowquerylogfile
        ls $dbparam_slowquerylogfile > /dev/null 2>&1
        if [ $? -ne 0 ]
        then
            log error "I can't access the slow query log in '$dbparam_slowquerylogfile' either"
            exit 1
        fi
    fi

    # Check slow query log file size
    sqfsize=`wc -c $dbparam_slowquerylogfile | awk '{print $1}' 2>/dev/null`
    if [ $sqfsize -gt 1073741824 ]
    then
        log warn "The slow query log file size is `echo 'scale=2 ; '$sqfsize' / 1073741824' | bc` Gb. It might take a while to process the slow queries"
    fi

    # Create query digest
    log info "I now will aggregate slow queries and compute some stats.."
    $parent_path/pt-query-digest \
        --output=json \
        --max-line-length=0 \
        --limit=10 \
        --no-version-check \
        --no-continue-on-error $dbparam_slowquerylogfile > $query_digest_file 2>>$log_file

    query_digest_lines=`wc -l $query_digest_file | awk '{print $1}'`
    if [ "$query_digest_lines" == "0" ]
    then
        log error "I was not able to extract any queries from the slow query log. The file is either empty or corrupted"
        exit 1
    fi

    # Request token or validate existing one
    token_request

    # Call twcollector to submit a job per slow query
    python twanalyze.py --db_user=$db_user --db_pass=$db_pass --db_host=$db_host --db_port=$db_port --db_sock=$db_sock --auth_token=$auth_token --db_name=$defaultdb --query_digest_file=$query_digest_file


    log info "Collection completed successfully"
    exit 0

}    

banner
main
