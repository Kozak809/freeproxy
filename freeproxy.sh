#!/bin/bash

BASE_URL="https://www.v2nodes.com"
CACHE_DIR="$HOME/.cache/freeproxy"
CACHE_FILE="$CACHE_DIR/servers_cache.txt"
CACHE_EXPIRY=3600  

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

COUNTRIES=()
DEEP_PAGES=1
RATING_COUNT=1
MAX_LATENCY=99
PROTOCOL="vless"
OUTPUT_FILE=""
COPY_TO_CLIPBOARD=false
VERBOSE=false
RANDOM_MODE=false
TEST_CONNECTION=false
INTERACTIVE=false
GENERATE_QR=false
USE_CACHE=false

show_help() {
    echo "Использование: $0 <коды_стран> [опции]"
    echo ""
    echo "Параметры:"
    echo "  <коды_стран>        Код страны или список через запятую (ru, us,de,fr)"
    echo ""
    echo "Опции поиска:"
    echo "  -d, --deep <N>      Количество страниц для поиска (по умолчанию: 1)"
    echo "  -r, --rating <N>    Топ N лучших серверов (по умолчанию: 1)"
    echo "  -m, --max-latency <N> Максимальная задержка в ms (по умолчанию: без лимита)"
    echo "  -p, --protocol <TYPE> Тип протокола: vless, vmess, trojan, all (по умолчанию: vless)"
    echo ""
    echo "Режимы вывода:"
    echo "  -c, --copy          Копировать первую ссылку в буфер обмена"
    echo "  -o, --output <FILE> Сохранить ссылки в файл"
    echo "  -v, --verbose       Подробная информация о серверах"
    echo "  -i, --interactive   Интерактивный выбор сервера"
    echo "  --qr                Показать QR-код для первой ссылки"
    echo "  --random            Выбрать случайный из топ-10"
    echo ""
    echo "Дополнительно:"
    echo "  --test              Проверить доступность серверов (ping)"
    echo "  --use-cache         Использовать кэш (быстрее, но может быть устаревшим)"
    echo "  --update-cache      Обновить кэш серверов"
    echo "  -h, --help          Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 ru"
    echo "  $0 ru -d 3 -r 5"
    echo "  $0 ru,us,de -r 1"
    echo "  $0 ru -m 100 -c"
    echo "  $0 ru -d 2 -r 3 -o servers.txt"
    echo "  $0 ru -i --qr"
    echo "  $0 ru --random --test"
    exit 0
}

colorize_latency() {
    local latency=$1
    if [ "$latency" -lt 100 ]; then
        echo -e "${GREEN}${latency}ms${NC}"
    elif [ "$latency" -lt 300 ]; then
        echo -e "${YELLOW}${latency}ms${NC}"
    else
        echo -e "${RED}${latency}ms${NC}"
    fi
}

create_vless_url() {
    local server="$1"
    local port="$2"
    local uuid="$3"
    local flow="$4"
    local encryption="$5"
    local security="$6"
    local sni="$7"
    local alpn="$8"
    local network="$9"
    local fingerprint="${10}"
    local pbk="${11}"
    local sid="${12}"
    local remark="${13}"
    
    local vless_url="vless://${uuid}@${server}:${port}?"
    
    [ -n "$encryption" ] && [ "$encryption" != "none" ] && vless_url+="encryption=${encryption}&"
    [ -n "$flow" ] && [ "$flow" != "none" ] && vless_url+="flow=${flow}&"
    [ -n "$security" ] && [ "$security" != "none" ] && vless_url+="security=${security}&"
    [ -n "$sni" ] && vless_url+="sni=${sni}&"
    [ -n "$alpn" ] && vless_url+="alpn=${alpn}&"
    [ -n "$network" ] && vless_url+="type=${network}&"
    [ -n "$fingerprint" ] && vless_url+="fp=${fingerprint}&"
    [ -n "$pbk" ] && vless_url+="pbk=${pbk}&"
    [ -n "$sid" ] && vless_url+="sid=${sid}&"
    
    vless_url="${vless_url%&}"
    [ -n "$remark" ] && vless_url+="#${remark}"
    
    echo "$vless_url"
}

get_server_config() {
    local server_id="$1"
    local latency="$2"
    local country="$3"
    
    local server_page=$(curl -s "${BASE_URL}/servers/${server_id}/")
    
    if [ -z "$server_page" ]; then
        return 1
    fi
    
    local config_block=$(echo "$server_page" | sed -n '/<pre class="rounded-4 bg-body-secondary/,/<\/pre>/p' | sed 's/<[^>]*>//g')
    
    local server=$(echo "$config_block" | grep "^Server:" | cut -d' ' -f2 | tr -d '\r')
    local port=$(echo "$config_block" | grep "^Port:" | cut -d' ' -f2 | tr -d '\r')
    local uuid=$(echo "$config_block" | grep "^UUID:" | cut -d' ' -f2 | tr -d '\r')
    local flow=$(echo "$config_block" | grep "^Flow:" | cut -d' ' -f2 | tr -d '\r')
    local encryption=$(echo "$config_block" | grep "^Encryption:" | cut -d' ' -f2 | tr -d '\r')
    local security=$(echo "$config_block" | grep "^Security:" | cut -d' ' -f2 | tr -d '\r')
    local sni=$(echo "$config_block" | grep "^SNI:" | cut -d' ' -f2 | tr -d '\r')
    local alpn=$(echo "$config_block" | grep "^ALPN:" | cut -d' ' -f2 | tr -d '\r')
    local network=$(echo "$config_block" | grep "^Network:" | cut -d' ' -f2 | tr -d '\r')
    local fingerprint=$(echo "$config_block" | grep "^Fingerprint:" | cut -d' ' -f2 | tr -d '\r')
    local pbk=$(echo "$config_block" | grep "^Reality Public Key:" | cut -d':' -f2 | xargs | tr -d '\r')
    local sid=$(echo "$config_block" | grep "^Reality Short ID:" | cut -d':' -f2 | xargs | tr -d '\r')
    
    local simple_remark="${country^^}-${server_id}"
    local vless_url=$(create_vless_url "$server" "$port" "$uuid" "$flow" "$encryption" "$security" "$sni" "$alpn" "$network" "$fingerprint" "$pbk" "$sid" "$simple_remark")
    
    echo "${latency}|${server_id}|${vless_url}|${server}|${port}|${security}|${network}"
}

test_server() {
    local server="$1"
    if command -v ping &> /dev/null; then
        if ping -c 1 -W 2 "$server" &> /dev/null; then
            echo -e "${GREEN}✓ Online${NC}"
        else
            echo -e "${RED}✗ Offline${NC}"
        fi
    else
        echo -e "${YELLOW}? Ping недоступен${NC}"
    fi
}

copy_to_clipboard() {
    local text="$1"
    if command -v xclip &> /dev/null; then
        echo -n "$text" | xclip -selection clipboard
        echo -e "${GREEN}✓ Скопировано в буфер обмена (xclip)${NC}"
    elif command -v xsel &> /dev/null; then
        echo -n "$text" | xsel --clipboard
        echo -e "${GREEN}✓ Скопировано в буфер обмена (xsel)${NC}"
    elif command -v pbcopy &> /dev/null; then
        echo -n "$text" | pbcopy
        echo -e "${GREEN}✓ Скопировано в буфер обмена (pbcopy)${NC}"
    else
        echo -e "${YELLOW}⚠ Утилита для копирования не найдена (установите xclip, xsel или pbcopy)${NC}"
    fi
}

generate_qr() {
    local text="$1"
    if command -v qrencode &> /dev/null; then
        qrencode -t ANSIUTF8 "$text"
    else
        echo -e "${YELLOW}⚠ qrencode не установлен (sudo apt install qrencode)${NC}"
    fi
}

update_cache() {
    mkdir -p "$CACHE_DIR"
    echo -e "${BLUE}Обновление кэша...${NC}"
    > "$CACHE_FILE"
    
    for country in "${COUNTRIES[@]}"; do
        for page in $(seq 1 3); do
            if [ $page -eq 1 ]; then
                url="${BASE_URL}/country/${country}/"
            else
                url="${BASE_URL}/country/${country}/?page=${page}"
            fi
            
            country_page=$(curl -s "$url")
            if [ -z "$country_page" ] || ! echo "$country_page" | grep -q 'class="col-md-12 servers"'; then
                break
            fi
            
            echo "$country_page" >> "$CACHE_FILE"
        done
    done
    
    echo -e "${GREEN}✓ Кэш обновлён${NC}"
    exit 0
}

POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -d|--deep)
            DEEP_PAGES="$2"
            shift 2
            ;;
        -r|--rating)
            RATING_COUNT="$2"
            shift 2
            ;;
        -m|--max-latency)
            MAX_LATENCY="$2"
            shift 2
            ;;
        -p|--protocol)
            PROTOCOL="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -c|--copy)
            COPY_TO_CLIPBOARD=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        --qr)
            GENERATE_QR=true
            shift
            ;;
        --random)
            RANDOM_MODE=true
            shift
            ;;
        --test)
            TEST_CONNECTION=true
            shift
            ;;
        --use-cache)
            USE_CACHE=true
            shift
            ;;
        --update-cache)
            IFS=',' read -ra COUNTRIES <<< "$2"
            update_cache
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"

if [ ${#POSITIONAL_ARGS[@]} -eq 0 ]; then
    echo -e "${RED}Ошибка: не указан код страны${NC}"
    show_help
fi

IFS=',' read -ra COUNTRIES <<< "${POSITIONAL_ARGS[0]}"

if ! [[ "$DEEP_PAGES" =~ ^[0-9]+$ ]] || [ "$DEEP_PAGES" -lt 1 ]; then
    echo -e "${RED}Ошибка: параметр -d должен быть положительным числом${NC}"
    exit 1
fi

if ! [[ "$RATING_COUNT" =~ ^[0-9]+$ ]] || [ "$RATING_COUNT" -lt 1 ]; then
    echo -e "${RED}Ошибка: параметр -r должен быть положительным числом${NC}"
    exit 1
fi

declare -a servers_array

for country in "${COUNTRIES[@]}"; do
    for page in $(seq 1 $DEEP_PAGES); do
        if [ $page -eq 1 ]; then
            url="${BASE_URL}/country/${country}/"
        else
            url="${BASE_URL}/country/${country}/?page=${page}"
        fi
        
        country_page=$(curl -s "$url")
        
        if [ -z "$country_page" ] || ! echo "$country_page" | grep -q 'class="col-md-12 servers"'; then
            break
        fi
        
        while IFS= read -r line; do
            if echo "$line" | grep -q 'class="col-md-12 servers"'; then
                server_id=$(echo "$line" | grep -oP 'data-id="\K\d+')
                latency_block=$(echo "$country_page" | grep -A 20 "data-id=\"${server_id}\"" | grep -oP '\d+(?=ms)')
                
                if [ -n "$latency_block" ]; then
                    latency=$latency_block
                    
                    if [ "$PROTOCOL" == "all" ]; then
                        protocol_match=1
                    elif [ "$PROTOCOL" == "vless" ]; then
                        protocol_match=$(echo "$country_page" | grep -A 5 "data-id=\"${server_id}\"" | grep -c "V2Ray Vless")
                    elif [ "$PROTOCOL" == "vmess" ]; then
                        protocol_match=$(echo "$country_page" | grep -A 5 "data-id=\"${server_id}\"" | grep -c "V2Ray Vmess")
                    elif [ "$PROTOCOL" == "trojan" ]; then
                        protocol_match=$(echo "$country_page" | grep -A 5 "data-id=\"${server_id}\"" | grep -c "Trojan")
                    else
                        protocol_match=0
                    fi
                    
                    if [ "$protocol_match" -gt 0 ] && [ "$latency" -le "$MAX_LATENCY" ]; then
                        servers_array+=("${latency}|${server_id}|${country}")
                    fi
                fi
            fi
        done <<< "$country_page"
    done
done

if [ ${#servers_array[@]} -eq 0 ]; then
    echo -e "${RED}Ошибка: не найдено серверов с заданными параметрами${NC}"
    exit 1
fi

IFS=$'\n' sorted_servers=($(sort -t'|' -k1 -n <<< "${servers_array[*]}"))
unset IFS

if [ "$RANDOM_MODE" = true ]; then
    max_index=$((${#sorted_servers[@]} < 10 ? ${#sorted_servers[@]} : 10))
    random_index=$((RANDOM % max_index))
    sorted_servers=("${sorted_servers[$random_index]}")
    RATING_COUNT=1
fi

declare -a configs_array
for server_info in "${sorted_servers[@]}"; do
    if [ ${#configs_array[@]} -ge $RATING_COUNT ]; then
        break
    fi
    
    latency=$(echo "$server_info" | cut -d'|' -f1)
    server_id=$(echo "$server_info" | cut -d'|' -f2)
    country=$(echo "$server_info" | cut -d'|' -f3)
    
    config=$(get_server_config "$server_id" "$latency" "$country")
    
    if [ -n "$config" ]; then
        configs_array+=("$config")
    fi
done

if [ "$INTERACTIVE" = true ] && [ ${#configs_array[@]} -gt 1 ]; then
    echo -e "${BLUE}Доступные серверы:${NC}"
    for i in "${!configs_array[@]}"; do
        config="${configs_array[$i]}"
        latency=$(echo "$config" | cut -d'|' -f1)
        server_id=$(echo "$config" | cut -d'|' -f2)
        server=$(echo "$config" | cut -d'|' -f4)
        
        echo -e "$((i+1)). ${server_id} ($(colorize_latency $latency)) - ${server}"
    done
    
    echo -n "Выберите сервер [1-${#configs_array[@]}]: "
    read choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#configs_array[@]} ]; then
        configs_array=("${configs_array[$((choice-1))]}")
    else
        echo -e "${RED}Ошибка: неверный выбор${NC}"
        exit 1
    fi
fi

first_url=""
for i in "${!configs_array[@]}"; do
    config="${configs_array[$i]}"
    latency=$(echo "$config" | cut -d'|' -f1)
    server_id=$(echo "$config" | cut -d'|' -f2)
    vless_url=$(echo "$config" | cut -d'|' -f3)
    server=$(echo "$config" | cut -d'|' -f4)
    port=$(echo "$config" | cut -d'|' -f5)
    security=$(echo "$config" | cut -d'|' -f6)
    network=$(echo "$config" | cut -d'|' -f7)
    
    if [ -z "$first_url" ]; then
        first_url="$vless_url"
    fi
    
    echo "Найден лучший сервер ID: ${server_id} с задержкой: $(colorize_latency $latency)"
    
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}  IP:${NC} ${server}"
        echo -e "${BLUE}  Port:${NC} ${port}"
        echo -e "${BLUE}  Security:${NC} ${security}"
        echo -e "${BLUE}  Network:${NC} ${network}"
        if [ "$TEST_CONNECTION" = true ]; then
            echo -n -e "${BLUE}  Status:${NC} "
            test_server "$server"
        fi
    fi
    
    echo "=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+="
    echo "$vless_url"
    echo "=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+="
    
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$vless_url" >> "$OUTPUT_FILE"
    fi
    
    if [ $i -lt $((${#configs_array[@]} - 1)) ]; then
        echo ""
    fi
done

if [ "$COPY_TO_CLIPBOARD" = true ] && [ -n "$first_url" ]; then
    copy_to_clipboard "$first_url"
fi

if [ "$GENERATE_QR" = true ] && [ -n "$first_url" ]; then
    echo ""
    generate_qr "$first_url"
fi

if [ -n "$OUTPUT_FILE" ]; then
    echo ""
    echo -e "${GREEN}✓ Сохранено в файл: ${OUTPUT_FILE}${NC}"
fi