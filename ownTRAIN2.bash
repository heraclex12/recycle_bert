#! /bin/bash
#
# Decoder training
#

trap 'exit 2' 2
DIR=$(cd $(dirname $0); pwd)

CODE=$DIR/user_code
export PYTHONPATH="$CODE:$PYTHONPATH"

BERT_MODEL=bert-base-uncased
CORPUS=$DIR/corpus
DATA=$DIR/data
SRC=en
TRG=sparql

MODEL_STAGE1=model.stage1
DROPOUT=0.3
LR=0.0004
WARMUP_EPOCHS=5
TRAIN_EPOCHS=200


### Set the mini-batch size to around 500 sentences.
GPUID=
TOKENS_PER_GPU=5000
UPDATE_FREQ=4

#
# Usage
#
usage_exit () {
    echo "Usage $0 [-s SRC] [-t TRG] [-g GPUIDs]" 1>&2
    exit 1
}

#
# Options
#
while getopts g:s:t:h OPT; do
    case $OPT in
        s)  SRC=$OPTARG
            ;;
        t)  TRG=$OPTARG
            ;;
        g)  GPUID=$OPTARG
            ;;
        h)  usage_exit
            ;;
        \?) usage_exit
            ;;
    esac
done
shift $((OPTIND - 1))
if [ -n "$GPUID" ]; then
    export CUDA_VISIBLE_DEVICES=$GPUID
fi

#
# Training
#

### Set training parameters related to a mini-batch.
if [ -n "$CUDA_VISIBLE_DEVICES" ]; then
    echo "CUDA Devices: $CUDA_VISIBLE_DEVICES" 1>&2
    num_gpus=`echo $CUDA_VISIBLE_DEVICES | awk -F, "{print NF}"`
    UPDATE_FREQ=$((4 / $num_gpus))
fi

### The corpus size is around 4.5 million sentences.
### The mini-batch size is set to around 500 sentences. 
UPDATES_PER_EPOCH=9000
DISP_FREQ=$((UPDATES_PER_EPOCH / 5))
WARMUP_FLOAT=`echo "$UPDATES_PER_EPOCH * $WARMUP_EPOCHS" | bc`
WARMUP=`printf "%.0f" $WARMUP_FLOAT`

training () {
    model=$1
    date
    fairseq-train $DATA -s $SRC -t $TRG \
	--ddp-backend no_c10d \
	--user-dir $CODE --task translation_with_bert \
	--bert-model $BERT_MODEL \
	--arch transformer_with_pretrained_bert \
	--fp16 \
	--no-progress-bar --log-format simple \
	--log-interval $DISP_FREQ \
	--max-tokens $TOKENS_PER_GPU --update-freq $UPDATE_FREQ \
	--max-epoch $TRAIN_EPOCHS \
	--optimizer adam --lr $LR --adam-betas '(0.9, 0.99)' \
	--label-smoothing 0.1 --clip-norm 5 \
	--dropout $DROPOUT \
	--min-lr '1e-09' --lr-scheduler inverse_sqrt \
	--weight-decay 0.0001 \
  --valid-subset test \
	--save-interval 50 \
	--criterion label_smoothed_cross_entropy \
	--warmup-updates 4000 --warmup-init-lr '1e-07' \
	--save-dir $model
    date
}

mkdir -p $MODEL_STAGE1
training $MODEL_STAGE1 > $MODEL_STAGE1/training.log
