#!/bin/bash
# Provisioning script para instancia vast.ai com ComfyUI.
# Colado direto na caixa "On-start Script" do vast.ai, na frente do
# "entrypoint.sh" que ja estava la: baixa os modelos primeiro e so depois
# chama o entrypoint original, que sobe o ComfyUI normalmente.
#
# Troque CIVITAI_TOKEN abaixo pela sua API key da Civitai
# (https://civitai.com/user/account -> API Keys). E necessaria porque alguns
# dos arquivos abaixo sao marcados NSFW e a Civitai exige autenticacao para
# baixa-los. Mantenha este repositorio PRIVADO, ja que a chave fica em texto
# puro aqui.
#
# Checkpoints baixados (models/checkpoints):
#   - Red Lily | Illu                    (modelVersionId 2343145)
#   - WAI-illustrious-SDXL v17           (modelVersionId 2883731)
#
# LoRAs baixados (models/loras):
#   - Detailer IL v2                     (modelVersionId 1736373)
#   - Dramatic Lighting Slider           (modelVersionId 1242203) [base: Pony]
#   - Stabilizer IL/NAI/CK               (modelVersionId 2055853)
#   - MoriiMee Gothic Niji               (modelVersionId 2498503)
#   - Pony: People's Works v6            (modelVersionId 1247042) [base: NoobAI]
#   - Ri-mix - Style LORA [Illu+Anima]   (modelVersionId 2811751)
#   - sexy details v5                    (modelVersionId 3002225)
#   - USNR STYLE                         (modelVersionId 1552087)

set -uo pipefail
# (sem "-e" de proposito: se um download falhar, o script deve seguir para
# os proximos arquivos e ainda assim chamar o entrypoint.sh no final, para
# nao deixar o ComfyUI sem subir por causa de um modelo so)

COMFYUI_DIR="${COMFYUI_DIR:-${WORKSPACE:-/workspace}/ComfyUI}"
CHECKPOINTS_DIR="${COMFYUI_DIR}/models/checkpoints"
LORAS_DIR="${COMFYUI_DIR}/models/loras"

CHECKPOINT_MODELS=(
    "2343145|redLilyIllu_v10.safetensors"
    "2883731|waiIllustriousSDXL_v170.safetensors"
)

LORA_MODELS=(
    "1736373|DetailerILv2-000008.safetensors"
    "1242203|DramaticLightingSlider.safetensors"
    "2055853|illustriousXLv01_stabilizer_v1.198.safetensors"
    "2498503|MoriiMee_Gothic_Realistic.safetensors"
    "1247042|ponyv6_noobV1_2_adamW-000017.safetensors"
    "2811751|rimixxO2.safetensors"
    "3002225|sexy_details_v5.safetensors"
    "1552087|USNR_STYLE_ILL_V1_lokr3-000024.safetensors"
)

function provisioning_print_header() {
    printf "\n##############################################\n"
    printf "#          Provisioning ComfyUI models        #\n"
    printf "##############################################\n\n"
}

function provisioning_wait_for_network() {
    local max_wait=120
    local waited=0
    printf "Aguardando rede ficar pronta...\n"
    until curl -sSf --max-time 5 -o /dev/null https://civitai.com; do
        waited=$((waited + 5))
        if [[ $waited -ge $max_wait ]]; then
            printf "  rede nao respondeu em %ss, seguindo mesmo assim\n" "$max_wait"
            return 0
        fi
        sleep 5
    done
    printf "Rede OK.\n"
}

function provisioning_download_civitai() {
    local model_version_id="$1"
    local filename="$2"
    local dest_dir="$3"
    local dest="${dest_dir}/${filename}"
    local url="https://civitai.com/api/download/models/${model_version_id}"

    if [[ -f "$dest" ]]; then
        printf "[skip] %s ja existe\n" "$filename"
        return 0
    fi

    local auth_header=()
    if [[ -n "${CIVITAI_TOKEN:-}" ]]; then
        auth_header=(--header "Authorization: Bearer ${CIVITAI_TOKEN}")
    else
        printf "  aviso: CIVITAI_TOKEN nao definido; o download pode falhar (401/403) para modelos com restricao.\n"
    fi

    local attempt
    for attempt in 1 2 3 4 5; do
        printf "[download] %s -> %s (tentativa %d/5)\n" "$filename" "$dest" "$attempt"
        if wget \
            --content-disposition \
            "${auth_header[@]}" \
            --timeout=30 \
            --tries=3 \
            --progress=dot:giga \
            -O "$dest" \
            "$url"; then
            return 0
        fi
        rm -f "$dest"
        printf "  tentativa %d/5 falhou, aguardando antes de tentar de novo...\n" "$attempt"
        sleep $((attempt * 10))
    done

    printf "  ERRO ao baixar %s apos varias tentativas (verifique CIVITAI_TOKEN / restricoes do modelo)\n" "$filename"
}

function provisioning_get_files() {
    local dest_dir="$1"
    shift
    mkdir -p "$dest_dir"
    for entry in "$@"; do
        local model_version_id="${entry%%|*}"
        local filename="${entry##*|}"
        provisioning_download_civitai "$model_version_id" "$filename" "$dest_dir"
    done
}

function provisioning_start() {
    provisioning_print_header
    provisioning_wait_for_network
    provisioning_get_files "$CHECKPOINTS_DIR" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files "$LORAS_DIR" "${LORA_MODELS[@]}"
    printf "\nProvisioning concluido.\n"
}

provisioning_start

