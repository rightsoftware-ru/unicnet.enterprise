#!/bin/bash

# Скрипт для генерации диаграммы зависимостей из docker-compose.yml

COMPOSE_FILE="../app/docker-compose.yml"
OUTPUT_DOT="dependencies_diagram.dot"
OUTPUT_PNG="dependencies_diagram.png"
OUTPUT_SVG="dependencies_diagram.svg"

# Цвета для сервисов
declare -A COLORS=(
    ["postgres"]="#1e88e5:#0d47a1"
    ["mongo"]="#43a047:#1b5e20"
    ["keycloak"]="#fb8c00:#e65100"
    ["logger"]="#616161:#212121"
    ["syslog"]="#616161:#212121"
    ["vault"]="#7b1fa2:#4a148c"
    ["router"]="#00897b:#004d40"
    ["backend"]="#e53935:#b71c1c"
    ["frontend"]="#d81b60:#880e4f"
)

# Функция для получения цвета сервиса
get_color() {
    local service=$1
    for key in "${!COLORS[@]}"; do
        if [[ "$service" == *"$key"* ]]; then
            echo "${COLORS[$key]}"
            return
        fi
    done
    echo "#757575:#424242"  # серый по умолчанию
}

# Начало DOT файла
cat > "$OUTPUT_DOT" << 'EOF'
digraph Dependencies {
    rankdir=TB;
    node [shape=box, style="rounded,filled", fontname="Arial", fontsize=12, fontcolor=white];
    edge [color=black, style=bold];
    
EOF

# Извлечение сервисов и зависимостей
current_service=""
in_depends_on=false

while IFS= read -r line; do
    # Определяем начало сервиса
    if [[ "$line" =~ ^[[:space:]]*unicnet\. ]]; then
        current_service=$(echo "$line" | sed 's/^[[:space:]]*\(unicnet\.[^:]*\):.*/\1/' | tr -d '[:space:]')
        in_depends_on=false
        continue
    fi
    
    # Определяем depends_on
    if [[ "$line" =~ depends_on: ]]; then
        in_depends_on=true
        continue
    fi
    
    # Извлекаем зависимости
    if [[ "$in_depends_on" == true ]] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*unicnet\. ]]; then
        dependency=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*\(unicnet\.[^[:space:]]*\).*/\1/' | tr -d '[:space:]')
        
        if [[ -n "$current_service" ]] && [[ -n "$dependency" ]]; then
            # Получаем короткие имена для узлов
            service_short=$(echo "$current_service" | sed 's/unicnet\.//')
            dep_short=$(echo "$dependency" | sed 's/unicnet\.//')
            
            # Получаем цвета
            service_colors=$(get_color "$service_short")
            dep_colors=$(get_color "$dep_short")
            
            service_fill=$(echo "$service_colors" | cut -d: -f1)
            service_stroke=$(echo "$service_colors" | cut -d: -f2)
            dep_fill=$(echo "$dep_colors" | cut -d: -f1)
            dep_stroke=$(echo "$dep_colors" | cut -d: -f2)
            
            # Добавляем узлы и связи
            echo "    ${dep_short} [label=\"${dependency}\", fillcolor=\"${dep_fill}\", color=\"${dep_stroke}\"];" >> "$OUTPUT_DOT"
            echo "    ${service_short} [label=\"${current_service}\", fillcolor=\"${service_fill}\", color=\"${service_stroke}\"];" >> "$OUTPUT_DOT"
            echo "    ${dep_short} -> ${service_short};" >> "$OUTPUT_DOT"
        fi
    fi
    
    # Сброс при новом сервисе или конце depends_on
    if [[ "$line" =~ ^[[:space:]]*[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]]*- ]]; then
        if [[ "$in_depends_on" == true ]] && [[ ! "$line" =~ depends_on ]]; then
            in_depends_on=false
        fi
    fi
    
done < "$COMPOSE_FILE"

# Закрываем DOT файл
echo "}" >> "$OUTPUT_DOT"

# Удаляем дубликаты узлов (оставляем последнее определение)
awk '!seen[$0]++' "$OUTPUT_DOT" > "${OUTPUT_DOT}.tmp" && mv "${OUTPUT_DOT}.tmp" "$OUTPUT_DOT"

# Генерируем изображения
if command -v dot &> /dev/null; then
    echo "Генерация PNG..."
    dot -Tpng "$OUTPUT_DOT" -o "$OUTPUT_PNG" 2>/dev/null && echo "✓ PNG создан: $OUTPUT_PNG"
    
    echo "Генерация SVG..."
    dot -Tsvg "$OUTPUT_DOT" -o "$OUTPUT_SVG" 2>/dev/null && echo "✓ SVG создан: $OUTPUT_SVG"
    
    echo ""
    echo "Диаграмма успешно создана!"
    ls -lh "$OUTPUT_DOT" "$OUTPUT_PNG" "$OUTPUT_SVG" 2>/dev/null
else
    echo "Ошибка: Graphviz (dot) не установлен"
    echo "Установите: sudo apt-get install graphviz"
    exit 1
fi

