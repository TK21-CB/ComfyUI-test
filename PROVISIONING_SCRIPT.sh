#!/bin/bash
# Provisioning script para instancia vast.ai com ComfyUI.
#
# Uso: hospede este arquivo num repo publico do GitHub e aponte a variavel
# de ambiente PROVISIONING_SCRIPT (na config da instancia vast.ai) para a
# URL raw dele, por exemplo:
#   https://raw.githubusercontent.com/SEU_USUARIO/SEU_REPO/main/provisioning_comfyui.sh
# O provisionador oficial do vast.ai (o mesmo que aparece nos logs como
# "Provisioning instance with manifest from /provisioning.yaml") busca essa
# URL e roda o script sozinho, com retry, sem precisar mexer no
# entrypoint.sh nem no On-start Script.
#
# Defina TAMBEM a variavel de ambiente CIVITAI_TOKEN (separada, NUNCA dentro
# deste arquivo) com sua API key da Civitai
# (https://civitai.com/user/account -> API Keys). E necessaria porque alguns
# dos arquivos abaixo sao marcados NSFW e a Civitai exige autenticacao para
# baixa-los. Como este arquivo fica em repo PUBLICO, jamais cole a chave
# aqui dentro.
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
#
# Embeddings baixados (models/embeddings):
#   - easynegative                       (modelVersionId 9208)
#   - lazypos                            (modelVersionId 1833157)
#   - lazyneg                            (modelVersionId 2121199)
#   - lazyhand                           (modelVersionId 2268235)

set -uo pipefail
# (sem "-e" de proposito: se um download falhar, o script deve seguir para
# os proximos arquivos em vez de abortar tudo)

COMFYUI_DIR="${COMFYUI_DIR:-${WORKSPACE:-/workspace}/ComfyUI}"
CHECKPOINTS_DIR="${COMFYUI_DIR}/models/checkpoints"
LORAS_DIR="${COMFYUI_DIR}/models/loras"
EMBEDDINGS_DIR="${COMFYUI_DIR}/models/embeddings"

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

EMBEDDING_MODELS=(
    "9208|easynegative.safetensors"
    "1833157|lazypos.safetensors"
    "2121199|lazyneg.safetensors"
    "2268235|lazyhand.safetensors"
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

    # Usa curl, nao wget: a Civitai redireciona alguns arquivos para storage
    # com auth via assinatura na propria URL (Cloudflare R2/AWS SigV4). O
    # wget reenvia nosso header Authorization mesmo apos o redirect, o que
    # colide com a assinatura da URL e derruba o download com 400 Bad
    # Request. O curl, por padrao, descarta o header Authorization ao
    # redirecionar para um host diferente, entao nao tem esse conflito.
    local attempt
    for attempt in 1 2 3 4 5; do
        printf "[download] %s -> %s (tentativa %d/5)\n" "$filename" "$dest" "$attempt"
        if curl -L --fail \
            "${auth_header[@]}" \
            --connect-timeout 30 \
            --speed-time 30 --speed-limit 10240 \
            --retry 3 --retry-delay 5 \
            -o "$dest" \
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
    provisioning_get_files "$EMBEDDINGS_DIR" "${EMBEDDING_MODELS[@]}"
    printf "\nProvisioning concluido.\n"
}

provisioning_start
