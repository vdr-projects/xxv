/*
 * Simple program to grab images from VDR Recording
 *
 * Copyright (c) 2005-2007 Andreas Brachold
 * 
 * based on FFmpeg main Copyright (c) 2000-2003 Fabrice Bellard
 *
 * This code is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This code is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 * Or, point your browser to http://www.gnu.org/copyleft/gpl.html
 */

#include <limits.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <string.h>

#include "ffm.h"

extern "C" {

#ifdef FFMDIR
#include <avutil.h>
#include <avcodec.h>
#include <avformat.h>
#include <swscale.h>
#else
#include <ffmpeg/avutil.h>
#include <ffmpeg/avcodec.h>
#include <ffmpeg/avformat.h>
#include <ffmpeg/swscale.h>
#endif
}

static int frame_width = 0;
static int frame_height = 0;
static float frame_aspect_ratio = 0;
static enum PixelFormat frame_pix_fmt = PIX_FMT_YUV420P;
static int frame_rate = 25;
static int frame_rate_base = 1;
static int keep_aspect_ratio = 1;

/** select an input file for an output file */
#define MAX_FILES 1

static AVFormatContext *input_files[MAX_FILES];
static int64_t input_files_ts_offset[MAX_FILES];
static unsigned int nb_input_files = 0;

static AVFormatContext *output_files[MAX_FILES];
static unsigned int nb_output_files = 0;

static AVInputFormat *file_iformat;
static AVOutputFormat *file_oformat;

static int max_frames[4] = {INT_MAX, INT_MAX, INT_MAX, INT_MAX};
static int video_qdiff = 3;


static char *video_rc_eq="tex^qComp";
static int me_method = ME_EPZS;

static int same_quality = 1;

static int top_field_first = -1;




static float mux_preload= 0.5;
static float mux_max_delay= 0.7;

static int64_t input_ts_offset = 0;

static int video_sync_method= 1;
static int opt_shortest = 0; //

static int verbose = 
#ifdef DEBUG
    2;
#else
    -1;
#endif

static int nb_frames_dup = 0;
static int nb_frames_drop = 0;
static int input_sync;

static int pgmyuv_compatibility_hack=0;
static int dts_delta_threshold = 10;

AVCodecContext *avctx_opts;
AVFormatContext *avformat_opts;
//static int64_t timer_start = 0;

struct AVInputStream;

typedef struct AVOutputStream {
    unsigned int file_index;          /* file index */
    int index;               /* stream index in the output file */
    int source_index;        /* AVInputStream index */
    AVStream *st;            /* stream in the output file */
    int encoding_needed;     /* true if encoding needed for this stream */
    int frame_number;
    /* input pts and corresponding output pts
       for A/V sync */
    //double sync_ipts;        /* dts from the AVPacket of the demuxer in second units */
    struct AVInputStream *sync_ist; /* input stream to sync against */
    int64_t sync_opts;       /* output frame counter, could be changed to some true timestamp */ //FIXME look at frame_number
    /* video only */
    int video_resample;
    AVFrame pict_tmp;      /* temporary image for resampling */
    struct SwsContext *img_resample_ctx; /* for image resampling */
    int resample_height;

} AVOutputStream;

typedef struct AVInputStream {
    unsigned int file_index;
    int index;
    AVStream *st;
    int discard;             /* true if stream data should be discarded */
    int decoding_needed;     /* true if the packets must be decoded in 'raw_fifo' */
    int64_t sample_index;      /* current sample */

    int64_t       start;     /* time when read started */
    unsigned long frame;     /* current frame */
    int64_t       next_pts;  /* synthetic pts for cases where pkt.pts
                                is not defined */
    int64_t       pts;       /* current pts */
    int is_start;            /* is 1 at the start and after a discontinuity */
} AVInputStream;

typedef struct AVInputFile {
    int eof_reached;      /* true if eof reached */
    int ist_index;        /* index of first stream in ist_table */
    int buffer_size;      /* current total buffer size */
    unsigned int nb_streams;       /* nb streams we are aware of */
} AVInputFile;

static double
get_sync_ipts(const AVOutputStream *ost)
{
    const AVInputStream *ist = ost->sync_ist;
    return (double)(ist->pts + input_files_ts_offset[ist->file_index] )/AV_TIME_BASE;
}

static int bit_buffer_size= 1024*256;
static uint8_t *bit_buffer= NULL;

static bool do_video_out(AVFormatContext *s,
                         AVOutputStream *ost,
                         AVInputStream *ist,
                         AVFrame *in_picture,
                         int *frame_size)
{
    int nb_frames, i, ret;
    AVFrame *final_picture, *formatted_picture, *resampling_dst, *padding_src;
    AVFrame picture_crop_temp, picture_pad_temp;
    AVCodecContext *enc, *dec;

    avcodec_get_frame_defaults(&picture_crop_temp);
    avcodec_get_frame_defaults(&picture_pad_temp);

    enc = ost->st->codec;
    dec = ist->st->codec;

    /* by default, we output a single frame */
    nb_frames = 1;

    *frame_size = 0;

    if(video_sync_method){
        double vdelta;
        vdelta = get_sync_ipts(ost) / av_q2d(enc->time_base) - ost->sync_opts;
        //FIXME set to 0.5 after we fix some dts/pts bugs like in avidec.c
        if (vdelta < -1.1)
            nb_frames = 0;
        else if (vdelta > 1.1)
            nb_frames = lrintf(vdelta);
//fprintf(stderr, "vdelta:%f, ost->sync_opts:%"PRId64", ost->sync_ipts:%f nb_frames:%d\n", vdelta, ost->sync_opts, ost->sync_ipts, nb_frames);
        if (nb_frames == 0){
            ++nb_frames_drop;
            if (verbose>2)
                fprintf(stderr, "*** drop!\n");
        }else if (nb_frames > 1) {
            nb_frames_dup += nb_frames;
            if (verbose>2)
                fprintf(stderr, "*** %d dup!\n", nb_frames-1);
        }
    }else
        ost->sync_opts= lrintf(get_sync_ipts(ost) / av_q2d(enc->time_base));

    nb_frames= FFMIN(nb_frames, max_frames[CODEC_TYPE_VIDEO] - ost->frame_number);
    if (nb_frames <= 0)
        return true;

    {
        formatted_picture = in_picture;
    }

    final_picture = formatted_picture;
    padding_src = formatted_picture;
    resampling_dst = &ost->pict_tmp;

    if (ost->video_resample) {
        padding_src = NULL;
        final_picture = &ost->pict_tmp;
        sws_scale(ost->img_resample_ctx, formatted_picture->data, formatted_picture->linesize,
              0, ost->resample_height, resampling_dst->data, resampling_dst->linesize);
    }

    /* duplicates frame if needed */
    for(i=0;i<nb_frames;i++) {
        AVPacket pkt;
        av_init_packet(&pkt);
        pkt.stream_index= ost->index;

        /*if (s->oformat->flags & AVFMT_RAWPICTURE) {
            // raw pictures are written as AVPicture structure to
            //   avoid any copies. We support temorarily the older
            //   method. 
            AVFrame* old_frame = enc->coded_frame;
            enc->coded_frame = dec->coded_frame; //FIXME/XXX remove this hack
            pkt.data= (uint8_t *)final_picture;
            pkt.size=  sizeof(AVPicture);
            if(dec->coded_frame && enc->coded_frame->pts != AV_NOPTS_VALUE)
                pkt.pts= av_rescale_q(enc->coded_frame->pts, enc->time_base, ost->st->time_base);
            if(dec->coded_frame && dec->coded_frame->key_frame)
                pkt.flags |= PKT_FLAG_KEY;

            av_interleaved_write_frame(s, &pkt);
            enc->coded_frame = old_frame;
        } else*/ {
            AVFrame big_picture;

            big_picture= *final_picture;
            /* better than nothing: use input picture interlaced
               settings */
            big_picture.interlaced_frame = in_picture->interlaced_frame;
            if(avctx_opts->flags & (CODEC_FLAG_INTERLACED_DCT|CODEC_FLAG_INTERLACED_ME)){
                if(top_field_first == -1)
                    big_picture.top_field_first = in_picture->top_field_first;
                else
                    big_picture.top_field_first = top_field_first;
            }

            /* handles sameq here. This is not correct because it may
               not be a global option */
            if (same_quality) {
                big_picture.quality = (int)ist->st->quality;
            }else
                big_picture.quality = (int)ost->st->quality;
                big_picture.pict_type = 0;
//            big_picture.pts = AV_NOPTS_VALUE;
            big_picture.pts= ost->sync_opts;
//            big_picture.pts= av_rescale(ost->sync_opts, AV_TIME_BASE*(int64_t)enc->time_base.num, enc->time_base.den);
//av_log(NULL, AV_LOG_DEBUG, "%"PRId64" -> encoder\n", ost->sync_opts);
            ret = avcodec_encode_video(enc,
                                       bit_buffer, bit_buffer_size,
                                       &big_picture);
            if (ret == -1) {
                fprintf(stderr, "Video encoding failed\n");
                return false;
            }
            //enc->frame_number = enc->real_pict_num;
            if(ret>0){
                pkt.data= bit_buffer;
                pkt.size= ret;
                if(enc->coded_frame && enc->coded_frame->pts != (int64_t)AV_NOPTS_VALUE)
                    pkt.pts= av_rescale_q(enc->coded_frame->pts, enc->time_base, ost->st->time_base);
/*av_log(NULL, AV_LOG_DEBUG, "encoder -> %"PRId64"/%"PRId64"\n",
   pkt.pts != AV_NOPTS_VALUE ? av_rescale(pkt.pts, enc->time_base.den, AV_TIME_BASE*(int64_t)enc->time_base.num) : -1,
   pkt.dts != AV_NOPTS_VALUE ? av_rescale(pkt.dts, enc->time_base.den, AV_TIME_BASE*(int64_t)enc->time_base.num) : -1);*/

                if(enc->coded_frame && enc->coded_frame->key_frame)
                    pkt.flags |= PKT_FLAG_KEY;
                av_interleaved_write_frame(s, &pkt);
                *frame_size = ret;
            }
        }
        ost->sync_opts++;
        ost->frame_number++;
    }
    return true;
}

/* pkt = NULL means EOF (needed to flush decoder buffers) */
static int output_packet(AVInputStream *ist, int ist_index,
                         AVOutputStream **ost_table, int nb_ostreams,
                         const AVPacket *pkt)
{
    AVFormatContext *os;
    AVOutputStream *ost;
    uint8_t *ptr;
    int len, ret, i;
    uint8_t *data_buf;
    int data_size, got_picture;
    AVFrame picture;
 
    if(!pkt){
        ist->pts= ist->next_pts; // needed for last packet if vsync=0
    } else if (pkt->dts != (int64_t)AV_NOPTS_VALUE) { //FIXME seems redundant, as libavformat does this too
        ist->next_pts = ist->pts = av_rescale_q(pkt->dts, ist->st->time_base, AV_TIME_BASE_Q);
    } else {
//        assert(ist->pts == ist->next_pts);
    }

    if (pkt == NULL) {
        /* EOF handling */
        ptr = NULL;
        len = 0;
        goto handle_eof;
    }

    len = pkt->size;
    ptr = pkt->data;
    while (len > 0) {
    handle_eof:
        /* decode the packet if needed */
        data_buf = NULL; /* fail safe */
        data_size = 0;
        if (ist->decoding_needed) {
            switch(ist->st->codec->codec_type) {
            case CODEC_TYPE_VIDEO:
                    data_size = (ist->st->codec->width * ist->st->codec->height * 3) / 2;
                    /* XXX: allocate picture correctly */
                    avcodec_get_frame_defaults(&picture);

                    ret = avcodec_decode_video(ist->st->codec,
                                               &picture, &got_picture, ptr, len);
                    ist->st->quality= picture.quality;
                    if (ret < 0)
                        goto fail_decode;
                    if (!got_picture) {
                        /* no picture yet */
                        goto discard_packet;
                    }
                    if (ist->st->codec->time_base.num != 0) {
                        ist->next_pts += ((int64_t)AV_TIME_BASE *
                                          ist->st->codec->time_base.num) /
                            ist->st->codec->time_base.den;
                    }
                    len = 0;
                    break;
            default:
                goto fail_decode;
            }
        } else {
            if(ist->st->codec->codec_type == CODEC_TYPE_VIDEO) {
                if (ist->st->codec->time_base.num != 0) {
                    ist->next_pts += ((int64_t)AV_TIME_BASE *
                                      ist->st->codec->time_base.num) /
                        ist->st->codec->time_base.den;
                }
            }
            data_buf = ptr;
            data_size = len;
            ret = len;
            len = 0;
        }

        /* frame rate emulation */
        if (ist->st->codec->rate_emu) {
            int64_t pts = av_rescale((int64_t) ist->frame * ist->st->codec->time_base.num, 1000000, ist->st->codec->time_base.den);
            int64_t now = av_gettime() - ist->start;
            if (pts > now)
                usleep(pts - now);

            ist->frame++;
        }

#if 0
        /* mpeg PTS deordering : if it is a P or I frame, the PTS
           is the one of the next displayed one */
        /* XXX: add mpeg4 too ? */
        if (ist->st->codec->codec_id == CODEC_ID_MPEG1VIDEO) {
            if (ist->st->codec->pict_type != B_TYPE) {
                int64_t tmp;
                tmp = ist->last_ip_pts;
                ist->last_ip_pts  = ist->frac_pts.val;
                ist->frac_pts.val = tmp;
            }
        }
#endif
        /* if output time reached then transcode raw format,
           encode packets and output them */
        if (1 || ist->pts >= 0)
            for(i=0;i<nb_ostreams;i++) {
                int frame_size;

                ost = ost_table[i];
                if (ost->source_index == ist_index) {
                    os = output_files[ost->file_index];

#if 0
                    printf("%d: got pts=%0.3f %0.3f\n", i,
                           (double)pkt->pts / AV_TIME_BASE,
                           ((double)ist->pts / AV_TIME_BASE) -
                           ((double)ost->st->pts.val * ost->st->time_base.num / ost->st->time_base.den));
#endif
                    /* set the input output pts pairs */
                    //ost->sync_ipts = (double)(ist->pts + input_files_ts_offset[ist->file_index])/ AV_TIME_BASE;

                    if (ost->encoding_needed) {
                        switch(ost->st->codec->codec_type) {
                        case CODEC_TYPE_VIDEO:
                            if(!do_video_out(os, ost, ist, &picture, &frame_size))
                               return -1;
                            break;
                        default:
                               return -1;
                        }
                    } else {
                        AVFrame avframe; //FIXME/XXX remove this
                        AVPacket opkt;
                        av_init_packet(&opkt);

                        /* no reencoding needed : output the packet directly */
                        /* force the input stream PTS */

                        avcodec_get_frame_defaults(&avframe);
                        ost->st->codec->coded_frame= &avframe;
                        avframe.key_frame = pkt->flags & PKT_FLAG_KEY;

                        if (ost->st->codec->codec_type == CODEC_TYPE_VIDEO) {
                            ost->sync_opts++;
                        }

                        opkt.stream_index= ost->index;
                        if(pkt->pts != (int64_t)AV_NOPTS_VALUE)
                            opkt.pts= av_rescale_q(av_rescale_q(pkt->pts, ist->st->time_base, AV_TIME_BASE_Q) + input_files_ts_offset[ist->file_index], AV_TIME_BASE_Q,  ost->st->time_base);
                        else
                            opkt.pts= AV_NOPTS_VALUE;

                        {
                            int64_t dts;
                            if (pkt->dts == (int64_t)AV_NOPTS_VALUE)
                                dts = ist->next_pts;
                            else
                                dts= av_rescale_q(pkt->dts, ist->st->time_base, AV_TIME_BASE_Q);
                            opkt.dts= av_rescale_q(dts + input_files_ts_offset[ist->file_index], AV_TIME_BASE_Q,  ost->st->time_base);
                        }
                        opkt.flags= pkt->flags;

                        //FIXME remove the following 2 lines they shall be replaced by the bitstream filters
                        if(av_parser_change(ist->st->parser, ost->st->codec, &opkt.data, &opkt.size, data_buf, data_size, pkt->flags & PKT_FLAG_KEY))
                            opkt.destruct= av_destruct_packet;

                        av_interleaved_write_frame(os, &opkt);
                        ost->st->codec->frame_number++;
                        ost->frame_number++;
                        av_free_packet(&opkt);
                    }
                }
            }
    }
 discard_packet:
    if (pkt == NULL) {
        /* EOF handling */

        for(i=0;i<nb_ostreams;i++) {
            ost = ost_table[i];
            if (ost->source_index == ist_index) {
                AVCodecContext *enc= ost->st->codec;
                os = output_files[ost->file_index];

                if(ost->st->codec->codec_type == CODEC_TYPE_VIDEO && (os->oformat->flags & AVFMT_RAWPICTURE))
                    continue;

                if (ost->encoding_needed) {
                    for(;;) {
                        AVPacket pkt;
                        av_init_packet(&pkt);
                        pkt.stream_index= ost->index;

                        switch(ost->st->codec->codec_type) {
                        case CODEC_TYPE_VIDEO:
                            ret = avcodec_encode_video(enc, bit_buffer, bit_buffer_size, NULL);
                            if(enc->coded_frame && enc->coded_frame->key_frame)
                                pkt.flags |= PKT_FLAG_KEY;
                            break;
                        default:
                            ret=-1;
                        }

                        if(ret<=0)
                            break;
                        pkt.data= bit_buffer;
                        pkt.size= ret;
                        if(enc->coded_frame && enc->coded_frame->pts != (int64_t)AV_NOPTS_VALUE)
                            pkt.pts= av_rescale_q(enc->coded_frame->pts, enc->time_base, ost->st->time_base);
                        av_interleaved_write_frame(os, &pkt);
                    }
                }
            }
        }
    }

    return 0;
 fail_decode:
    return -1;
}


/*
 * The following code is the main loop of the file converter
 */
static bool av_encode(AVFormatContext **output_files,
                     unsigned int nb_output_files,
                     AVFormatContext **input_files,
                     unsigned int nb_input_files)
{
    unsigned int i, j, k, n, nb_istreams = 0, nb_ostreams = 0;
    AVFormatContext *is, *os;
    AVCodecContext *codec, *icodec;
    AVOutputStream *ost, **ost_table = NULL;
    AVInputStream *ist, **ist_table = NULL;
    AVInputFile *file_table;
    bool ret;

    file_table= (AVInputFile*) av_mallocz(nb_input_files * sizeof(AVInputFile));
    if (!file_table)
        goto fail;

    /* input stream init */
    j = 0;
    for(i=0;i<nb_input_files;i++) {
        is = input_files[i];
        file_table[i].ist_index = j;
        file_table[i].nb_streams = is->nb_streams;
        j += is->nb_streams;
    }
    nb_istreams = j;

    ist_table = (AVInputStream**)av_mallocz(nb_istreams * sizeof(AVInputStream *));
    if (!ist_table)
        goto fail;

    for(i=0;i<nb_istreams;i++) {
        ist = (AVInputStream*)av_mallocz(sizeof(AVInputStream));
        if (!ist)
            goto fail;
        ist_table[i] = ist;
    }
    j = 0;
    for(i=0;i<nb_input_files;i++) {
        is = input_files[i];
        for(k=0;k<is->nb_streams;k++) {
            ist = ist_table[j++];
            ist->st = is->streams[k];
            ist->file_index = i;
            ist->index = k;
            ist->discard = 1; /* the stream is discarded by default
                                 (changed later) */

            if (ist->st->codec->rate_emu) {
                ist->start = av_gettime();
                ist->frame = 0;
            }
        }
    }

    /* output stream init */
    nb_ostreams = 0;
    for(i=0;i<nb_output_files;i++) {
        os = output_files[i];
        if (!os->nb_streams) {
            fprintf(stderr, "Output file does not contain any stream\n");
            return false;
        }
        nb_ostreams += os->nb_streams;
    }

    ost_table = (AVOutputStream**)av_mallocz(sizeof(AVOutputStream *) * nb_ostreams);
    if (!ost_table)
        goto fail;
    for(i=0;i<nb_ostreams;i++) {
        ost = (AVOutputStream*)av_mallocz(sizeof(AVOutputStream));
        if (!ost)
            goto fail;
        ost_table[i] = ost;
    }

    n = 0;
    for(k=0;k<nb_output_files;k++) {
        os = output_files[k];
        for(i=0;i<os->nb_streams;i++) {
            int found;
            ost = ost_table[n++];
            ost->file_index = k;
            ost->index = i;
            ost->st = os->streams[i];
            {
                /* get corresponding input stream index : we select the first one with the right type */
                found = 0;
                for(j=0;j<nb_istreams;j++) {
                    ist = ist_table[j];
                    if (ist->discard &&
                        ist->st->codec->codec_type == ost->st->codec->codec_type) {
                        ost->source_index = j;
                        found = 1;
                        break;
                    }
                }

                if (!found) {
                    /* try again and reuse existing stream */
                    for(j=0;j<nb_istreams;j++) {
                        ist = ist_table[j];
                        if (ist->st->codec->codec_type == ost->st->codec->codec_type) {
                            ost->source_index = j;
                            found = 1;
                        }
                    }
                    if (!found) {
                        fprintf(stderr, "Could not find input stream matching output stream #%d.%d\n",
                                ost->file_index, ost->index);
                        return false;
                    }
                }
            }
            ist = ist_table[ost->source_index];
            ist->discard = 0;
            ost->sync_ist = ist;
        }
    }

    /* for each output stream, we compute the right encoding parameters */
    for(i=0;i<nb_ostreams;i++) {
        ost = ost_table[i];
        ist = ist_table[ost->source_index];

        codec = ost->st->codec;
        icodec = ist->st->codec;

        if (ost->st->stream_copy) {
            /* if stream_copy is selected, no need to decode or encode */
            codec->codec_id = icodec->codec_id;
            codec->codec_type = icodec->codec_type;
            if(!codec->codec_tag) codec->codec_tag = icodec->codec_tag;
            codec->bit_rate = icodec->bit_rate;
            codec->extradata= icodec->extradata;
            codec->extradata_size= icodec->extradata_size;
            if(av_q2d(icodec->time_base) > av_q2d(ist->st->time_base) && av_q2d(ist->st->time_base) < 1.0/1000)
                codec->time_base = icodec->time_base;
            else
                codec->time_base = ist->st->time_base;
            switch(codec->codec_type) {
            case CODEC_TYPE_VIDEO:
                codec->pix_fmt = icodec->pix_fmt;
                codec->width = icodec->width;
                codec->height = icodec->height;
                codec->has_b_frames = icodec->has_b_frames;
                break;
            case CODEC_TYPE_SUBTITLE:
                break;
            default:
                return false;
            }
        } else {
            switch(codec->codec_type) {
            case CODEC_TYPE_VIDEO:
                ost->video_resample = ((codec->width != icodec->width) ||
                        (codec->height != icodec->height) ||
                        (codec->pix_fmt != icodec->pix_fmt));
                if (ost->video_resample) {
                    avcodec_get_frame_defaults(&ost->pict_tmp);
                    if( avpicture_alloc( (AVPicture*)&ost->pict_tmp, codec->pix_fmt,
                                         codec->width, codec->height ) ) {
                        fprintf(stderr, "Cannot allocate temp picture, check pix fmt\n");
                        return false;
                    }
                    ost->img_resample_ctx = sws_getContext(
                            icodec->width,
                            icodec->height,
                            icodec->pix_fmt,
                            codec->width,
                            codec->height,
                            codec->pix_fmt,
                            SWS_FAST_BILINEAR, NULL, NULL, NULL);
                    if (ost->img_resample_ctx == NULL) {
                        fprintf(stderr, "Cannot get resampling context\n");
                        return false;
                    }
                    ost->resample_height = icodec->height;
                }
                ost->encoding_needed = 1;
                ist->decoding_needed = 1;
                break;
            default:
                return false;
            }
        }
        if(codec->codec_type == CODEC_TYPE_VIDEO){
            int size= codec->width * codec->height;
            bit_buffer_size= FFMAX(bit_buffer_size, 4*size);
        }
    }

    if (!bit_buffer)
        bit_buffer = (uint8_t*)av_malloc(bit_buffer_size);
    if (!bit_buffer)
        goto fail;

    /* dump the file output parameters - cannot be done before in case
       of stream copy */
    for(i=0;i<nb_output_files;i++) {
        dump_format(output_files[i], i, output_files[i]->filename, 1);
    }

    /* open each encoder */
    for(i=0;i<nb_ostreams;i++) {
        ost = ost_table[i];
        if (ost->encoding_needed) {
            AVCodec *codec;
            codec = avcodec_find_encoder(ost->st->codec->codec_id);
            if (!codec) {
                fprintf(stderr, "Unsupported codec for output stream #%d.%d\n",
                        ost->file_index, ost->index);
                return false;
            }
            if (avcodec_open(ost->st->codec, codec) < 0) {
                fprintf(stderr, "Error while opening codec for output stream #%d.%d - maybe incorrect parameters such as bit_rate, rate, width or height\n",
                        ost->file_index, ost->index);
                return false;
            }
        }
    }

    /* open each decoder */
    for(i=0;i<nb_istreams;i++) {
        ist = ist_table[i];
        if (ist->decoding_needed) {
            AVCodec *codec;
            codec = avcodec_find_decoder(ist->st->codec->codec_id);
            if (!codec) {
                fprintf(stderr, "Unsupported codec (id=%d) for input stream #%d.%d\n",
                        ist->st->codec->codec_id, ist->file_index, ist->index);
                return false;
            }
            if (avcodec_open(ist->st->codec, codec) < 0) {
                fprintf(stderr, "Error while opening codec for input stream #%d.%d\n",
                        ist->file_index, ist->index);
                return false;
            }
            //if (ist->st->codec->codec_type == CODEC_TYPE_VIDEO)
            //    ist->st->codec->flags |= CODEC_FLAG_REPEAT_FIELD;
        }
    }

    /* init pts */
    for(i=0;i<nb_istreams;i++) {
        ist = ist_table[i];
        is = input_files[ist->file_index];
        ist->pts = 0;
        ist->next_pts = av_rescale_q(ist->st->start_time, ist->st->time_base, AV_TIME_BASE_Q);
        if(ist->st->start_time == (int64_t)AV_NOPTS_VALUE)
            ist->next_pts=0;
        if(input_files_ts_offset[ist->file_index])
            ist->next_pts= AV_NOPTS_VALUE;
        ist->is_start = 1;
    }

    /* open files and write file headers */
    for(i=0;i<nb_output_files;i++) {
        os = output_files[i];
        if (av_write_header(os) < 0) {
            fprintf(stderr, "Could not write header for output file #%d (incorrect codec parameters ?)\n", i);
            ret = false; //AVERROR(EINVAL);
            goto fail;
        }
    }

    //timer_start = av_gettime();

    while( 1 ) {
        unsigned int file_index, ist_index;
        AVPacket pkt;
        double ipts_min;
        double opts_min;

    redo:
        ipts_min= 1e100;
        opts_min= 1e100;

        /* select the stream that we must read now by looking at the
           smallest output pts */
        file_index = (unsigned int)-1;
        for(i=0;i<nb_ostreams;i++) {
            double ipts, opts;
            ost = ost_table[i];
            os = output_files[ost->file_index];
            ist = ist_table[ost->source_index];
            if(ost->st->codec->codec_type == CODEC_TYPE_VIDEO)
                opts = ost->sync_opts * av_q2d(ost->st->codec->time_base);
            else
                opts = ost->st->pts.val * av_q2d(ost->st->time_base);
            ipts = (double)ist->pts;
            if (!file_table[ist->file_index].eof_reached){
                if(ipts < ipts_min) {
                    ipts_min = ipts;
                    if(input_sync ) file_index = ist->file_index;
                }
                if(opts < opts_min) {
                    opts_min = opts;
                    if(!input_sync) file_index = ist->file_index;
                }
            }
            if(ost->frame_number >= max_frames[ost->st->codec->codec_type]){
                file_index= (unsigned int)-1;
                break;
            }
        }
        /* if none, if is finished */
        if (file_index == (unsigned int)-1) {
            break;
        }

        /* read a frame from it and output it in the fifo */
        is = input_files[file_index];
        if (av_read_frame(is, &pkt) < 0) {
            file_table[file_index].eof_reached = 1;
            if (opt_shortest) break; else continue; //
        }

        /* the following test is needed in case new streams appear
           dynamically in stream : we ignore them */
        if ((unsigned int)pkt.stream_index >= file_table[file_index].nb_streams)
            goto discard_packet;
        ist_index = file_table[file_index].ist_index + pkt.stream_index;
        ist = ist_table[ist_index];
        if (ist->discard)
            goto discard_packet;

//        fprintf(stderr, "next:%"PRId64" dts:%"PRId64" off:%"PRId64" %d\n", ist->next_pts, pkt.dts, input_files_ts_offset[ist->file_index], ist->st->codec->codec_type);
        if (pkt.dts != (int64_t)AV_NOPTS_VALUE && ist->next_pts != (int64_t)AV_NOPTS_VALUE) {
            int64_t delta= av_rescale_q(pkt.dts, ist->st->time_base, AV_TIME_BASE_Q) - ist->next_pts;
            if(FFABS(delta) > 1LL*dts_delta_threshold*AV_TIME_BASE){
                input_files_ts_offset[ist->file_index]-= delta;
//                if (verbose > 2)
//                    fprintf(stderr, "timestamp discontinuity %"PRId64", new offset= %"PRId64"\n", delta, input_files_ts_offset[ist->file_index]);
                for(i=0; i<file_table[file_index].nb_streams; i++){
                    int index= file_table[file_index].ist_index + i;
                    ist_table[index]->next_pts += delta;
                    ist_table[index]->is_start=1;
                }
            }
        }

        //fprintf(stderr,"read #%d.%d size=%d\n", ist->file_index, ist->index, pkt.size);
        if (output_packet(ist, ist_index, ost_table, nb_ostreams, &pkt) < 0) {

            if (verbose >= 0)
                fprintf(stderr, "Error while decoding stream #%d.%d\n",
                        ist->file_index, ist->index);

            av_free_packet(&pkt);
            goto redo;
        }

    discard_packet:
        av_free_packet(&pkt);

    }

    /* at the end of stream, we must flush the decoder buffers */
    for(i=0;i<nb_istreams;i++) {
        ist = ist_table[i];
        if (ist->decoding_needed) {
            output_packet(ist, i, ost_table, nb_ostreams, NULL);
        }
    }

    /* write the trailer if needed and close file */
    for(i=0;i<nb_output_files;i++) {
        os = output_files[i];
        av_write_trailer(os);
    }

    /* close each encoder */
    for(i=0;i<nb_ostreams;i++) {
        ost = ost_table[i];
        if (ost->encoding_needed) {
            av_freep(&ost->st->codec->stats_in);
            avcodec_close(ost->st->codec);
        }
    }

    /* close each decoder */
    for(i=0;i<nb_istreams;i++) {
        ist = ist_table[i];
        if (ist->decoding_needed) {
            avcodec_close(ist->st->codec);
        }
    }

    /* finished ! */

    ret = true;
 fail1:
    av_freep(&bit_buffer);
    av_free(file_table);

    if (ist_table) {
        for(i=0;i<nb_istreams;i++) {
            ist = ist_table[i];
            av_free(ist);
        }
        av_free(ist_table);
    }
    if (ost_table) {
        for(i=0;i<nb_ostreams;i++) {
            ost = ost_table[i];
            if (ost) {
                av_free(ost->pict_tmp.data[0]);
                if (ost->video_resample)
                    sws_freeContext(ost->img_resample_ctx);
                av_free(ost);
            }
        }
        av_free(ost_table);
    }
    return ret;
 fail:
    ret = false; //AVERROR(ENOMEM);
    goto fail1;
}

void print_error(const char *filename, int err)
{
    switch(err) {
    case AVERROR_NUMEXPECTED:
        fprintf(stderr, "%s: Incorrect image filename syntax.\n", 
                filename);
        break;
    case AVERROR_INVALIDDATA:
        fprintf(stderr, "%s: Error while parsing header\n", filename);
        break;
    case AVERROR_NOFMT:
        fprintf(stderr, "%s: Unknown format\n", filename);
        break;
    case AVERROR_IO:
        fprintf(stderr, "%s: I/O error occured\n"
	        "Usually that means that input file is truncated and/or corrupted.\n",
		filename);
        break;
    case AVERROR_NOMEM:
        fprintf(stderr, "%s: memory allocation error occured\n", filename);
        break;
    default:
        fprintf(stderr, "%s: Error while opening file\n", filename);
        break;
    }
}

static bool opt_input_file(const char *filename)
{
    AVFormatContext *ic;
    AVFormatParameters params, *ap = &params;
    int err, ret, rfps, rfps_base;
    unsigned int i;
    int64_t timestamp;

    /* get default parameters from command line */
    ic = av_alloc_format_context();

    memset(ap, 0, sizeof(*ap));
    ap->prealloced_context = 1;
    ap->time_base.den = frame_rate;
    ap->time_base.num = frame_rate_base;
    ap->width = frame_width + 0 + 0;
    ap->height = frame_height + 0 + 0;
    ap->pix_fmt = frame_pix_fmt;
    ap->channel = 0;
    ap->standard = 0;
    ap->video_codec_id = CODEC_ID_NONE;
    if(pgmyuv_compatibility_hack)
        ap->video_codec_id= CODEC_ID_PGMYUV;

    /* open the input file with generic libav function */
    err = av_open_input_file(&ic, filename, file_iformat, 0, ap);
    if (err < 0) {
        print_error(filename, err);
        return 0;
    }

    ic->loop_input = 0;

    /* If not enough info to get the stream parameters, we decode the
       first frames to get it. (used in mpeg case for example) */
    ret = av_find_stream_info(ic);
    if (ret < 0 && verbose >= 0) {
        fprintf(stderr, "%s: could not find codec parameters\n", filename);
        return false;
    }

    timestamp = 0;
    /* add the stream start time */
    if (ic->start_time != (int64_t)AV_NOPTS_VALUE)
        timestamp += ic->start_time;

    /* update the current parameters so that they match the one of the input stream */
    for(i=0;i<ic->nb_streams;i++) {
        AVCodecContext *enc = ic->streams[i]->codec;
        enc->thread_count= 1;
        switch(enc->codec_type) {
        case CODEC_TYPE_VIDEO:
            frame_height = enc->height;
            frame_width = enc->width;
            frame_aspect_ratio = av_q2d(enc->sample_aspect_ratio) * enc->width / enc->height;
            frame_pix_fmt = enc->pix_fmt;
            rfps      = ic->streams[i]->r_frame_rate.num;
            rfps_base = ic->streams[i]->r_frame_rate.den;
            if(enc->lowres) enc->flags |= CODEC_FLAG_EMU_EDGE;

            if (enc->time_base.den != rfps || enc->time_base.num != rfps_base) {

                if (verbose >= 0)
                    fprintf(stderr,"\nSeems stream %d codec frame rate differs from container frame rate: %2.2f (%d/%d) -> %2.2f (%d/%d)\n",
                            i, (float)enc->time_base.den / enc->time_base.num, enc->time_base.den, enc->time_base.num,

                    (float)rfps / rfps_base, rfps, rfps_base);
            }
            /* update the current frame rate to match the stream frame rate */
            frame_rate      = rfps;
            frame_rate_base = rfps_base;

            enc->rate_emu = 0;
            break;
        case CODEC_TYPE_DATA:
            break;
        case CODEC_TYPE_SUBTITLE:
            break;
        case CODEC_TYPE_UNKNOWN:
            break;
        default:
            //av_abort();
            return false;
        }
    }

    input_files[nb_input_files] = ic;
    input_files_ts_offset[nb_input_files] = input_ts_offset - timestamp;
    /* dump the file content */
    if (verbose >= 0)
        dump_format(ic, nb_input_files, filename, 0);

    nb_input_files++;
    file_iformat = NULL;
    file_oformat = NULL;
    return true;
}

static void check_video_inputs(int *has_video_ptr)
{
    int has_video;
    unsigned int i, j;
    AVFormatContext *ic;

    has_video = 0;
    for(j=0;j<nb_input_files;j++) {
        ic = input_files[j];
        for(i=0;i<ic->nb_streams;i++) {
            AVCodecContext *enc = ic->streams[i]->codec;
            switch(enc->codec_type) {
            case CODEC_TYPE_VIDEO:
                has_video = 1;
                break;
            case CODEC_TYPE_DATA:
            case CODEC_TYPE_UNKNOWN:
            case CODEC_TYPE_SUBTITLE:
                break;
            default:
                //av_abort();
                return;
            }
        }
    }
    *has_video_ptr = has_video;
}


static bool new_video_stream(AVFormatContext *oc)
{
    AVStream *st;
    AVCodecContext *video_enc;
    CodecID codec_id;

    st = av_new_stream(oc, oc->nb_streams);
    if (!st) {
        fprintf(stderr, "Could not alloc stream\n");
        return false;
    }
    avcodec_get_context_defaults2(st->codec, CODEC_TYPE_VIDEO);

    video_enc = st->codec;

    {
        AVCodec *codec;

        codec_id = av_guess_codec(oc->oformat, NULL, oc->filename, NULL, CODEC_TYPE_VIDEO);

        video_enc->codec_id = codec_id;
        codec = avcodec_find_encoder(codec_id);

        video_enc->time_base.den = frame_rate;
        video_enc->time_base.num = frame_rate_base;
/*      if(codec && codec->supported_framerates){
            const AVRational *p= codec->supported_framerates;
            AVRational req= (AVRational){frame_rate, frame_rate_base};
            const AVRational *best=NULL;
            AVRational best_error= (AVRational){INT_MAX, 1};
            for(; p->den!=0; p++){
                AVRational error= av_sub_q(req, *p);
                if(error.num <0) error.num *= -1;
                if(av_cmp_q(error, best_error) < 0){
                    best_error= error;
                    best= p;
                }
            }
            video_enc->time_base.den= best->num;
            video_enc->time_base.num= best->den;
        }*/

        if((keep_aspect_ratio & 2) == keep_aspect_ratio) { // Nur Höhe wurde definiert
    		video_enc->width = ((int)((float)frame_height * frame_aspect_ratio)) & 0x7ffffff8;
	       	video_enc->height = frame_height;
        } else if((keep_aspect_ratio & 1) == keep_aspect_ratio) { // Nur Weite wurde definiert
	       	video_enc->width = frame_width;
    		video_enc->height = ((int)((float)frame_width / frame_aspect_ratio)) & 0x7ffffff8;
        } else {
    		video_enc->width = frame_width;
	       	video_enc->height = frame_height;
        }

        video_enc->sample_aspect_ratio = av_d2q(frame_aspect_ratio*video_enc->height/video_enc->width, 255);
        video_enc->pix_fmt = frame_pix_fmt;

        if(codec && codec->pix_fmts){
            const enum PixelFormat *p= codec->pix_fmts;
            for(; *p!=-1; p++){
                if(*p == video_enc->pix_fmt)
                    break;
            }
            if(*p == -1)
                video_enc->pix_fmt = codec->pix_fmts[0];
        }

/*      if (intra_only)
            video_enc->gop_size = 0;*/
        if (same_quality) {
            video_enc->flags |= CODEC_FLAG_QSCALE;
            st->quality = FF_QP2LAMBDA;
            video_enc->global_quality= (int)st->quality;
        }

        video_enc->max_qdiff = video_qdiff;
        video_enc->rc_eq = video_rc_eq;
        video_enc->thread_count = 1;
        video_enc->rc_override_count=0;
        if (!video_enc->rc_initial_buffer_occupancy)
            video_enc->rc_initial_buffer_occupancy = video_enc->rc_buffer_size*3/4;
        video_enc->me_threshold= 0;
        video_enc->intra_dc_precision= 0;
        video_enc->strict_std_compliance = 0;

        video_enc->me_method = me_method;

    }

    return true;
}

/**
 * Copy the string str to buf. If str length is bigger than buf_size -
 * 1 then it is clamped to buf_size - 1.
 * NOTE: this function does what strncpy should have done to be
 * useful. NEVER use strncpy.
 * 
 * @param buf destination buffer
 * @param buf_size size of destination buffer
 * @param str source string
 */
void pstrcpy(char *buf, int buf_size, const char *str)
{
    int c;
    char *q = buf;

    if (buf_size <= 0)
        return;

    for(;;) {
        c = *str++;
        if (c == 0 || q >= buf + buf_size - 1)
            break;
        *q++ = c;
    }
    *q = '\0';
}

static bool opt_output_file(const char *filename)
{
    AVFormatContext *oc;
    int use_video, input_has_video = 0;
    AVFormatParameters params, *ap = &params;

    oc = av_alloc_format_context();

    if (!file_oformat) {
        file_oformat = guess_format(NULL, filename, NULL);
        if (!file_oformat) {
            fprintf(stderr, "Unable for find a suitable output format for '%s'\n",
                    filename);
            return false;
        }
    }

    oc->oformat = file_oformat;
    pstrcpy(oc->filename, sizeof(oc->filename), filename);

    {
        use_video = file_oformat->video_codec != CODEC_ID_NONE;

        /* disable if no corresponding type found and at least one
           input file */
        if (nb_input_files > 0) {
            check_video_inputs(&input_has_video);
            if (!input_has_video)
                use_video = 0;
        }

        if (use_video) {
            if(!new_video_stream(oc))
                return false;
        }

        oc->timestamp = 0;

    }

    output_files[nb_output_files++] = oc;

    /* check filename in case of an image number is expected */
    if (oc->oformat->flags & AVFMT_NEEDNUMBER) {
        if (!av_filename_number_test(oc->filename)) {
            print_error(oc->filename, AVERROR_NUMEXPECTED);
            return false;
        }
    }

    memset(ap, 0, sizeof(*ap));
    if (av_set_parameters(oc, ap) < 0) {
        fprintf(stderr, "%s: Invalid encoding parameters\n",
                oc->filename);
        return false;
    }

    oc->preload= (int)(mux_preload*AV_TIME_BASE);
    oc->max_delay= (int)(mux_max_delay*AV_TIME_BASE);
    oc->loop_output = AVFMT_NOOUTPUTLOOP;

    /* reset some options */
    file_oformat = NULL;
    file_iformat = NULL;
    return true;
}


void ffm_initalize(void)
{
    av_log_set_level(verbose);
    av_register_all();
    avctx_opts= avcodec_alloc_context();
}

void ffm_deinitalize(void)
{
    //av_free_static();
}

 

bool decode (const char* szMPVfile, /* const tPackedList & packed, */
             const char* szTmpMask, 
             int width, int height)
{
    unsigned int i,j;
    nb_input_files = 0;
    nb_output_files = 0;

    frame_width = 0;
    frame_height = 0;
    frame_aspect_ratio = 0;
    frame_pix_fmt = PIX_FMT_YUV420P;
    frame_rate = 25;
    frame_rate_base = 1;
    keep_aspect_ratio = 1;

    /* parse options */
    if(!opt_input_file(szMPVfile))
        return false;

    if (width != -1 || height != -1) {
    	if (width != -1) {
    		frame_width = width;
            keep_aspect_ratio |= 1;
        } else {
            keep_aspect_ratio &= ~1;
        }

    	if (height != -1) {
    		frame_height = height;
            keep_aspect_ratio |= 2;
        } else {
            keep_aspect_ratio &= ~2;
        }
    }

    if(!opt_output_file (szTmpMask))
        return false;

    /* file converter / grab */
    if (nb_output_files <= 0) {
        fprintf(stderr, "Must supply at least one output file\n");
        return false;
    }
    
    if (nb_input_files <= 0) {
        fprintf(stderr, "Must supply at least one input file\n");
        return false;
    }

    bool bRet = av_encode(output_files, nb_output_files, input_files, nb_input_files);

    /* close files */
    for(i=0;i<nb_output_files;i++) {
        /* maybe av_close_output_file ??? */
        AVFormatContext *s = output_files[i];

        if (!(s->oformat->flags & AVFMT_NOFILE))
	    url_fclose(&s->pb);
	for(j=0;j<s->nb_streams;j++)
	    av_free(s->streams[j]);
        av_free(s);
    }
    for(i=0;i<nb_input_files;i++)
        av_close_input_file(input_files[i]);

	return bRet;
}

