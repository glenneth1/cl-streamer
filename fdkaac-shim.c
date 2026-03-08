/* Shim for FDK-AAC encoder initialization.
   SBCL's signal handlers conflict with FDK-AAC's internal memory access,
   causing recursive SIGSEGV when calling aacEncEncode or aacEncOpen from
   CFFI. This shim does the entire open+configure+init from C. */

#include <fdk-aac/aacenc_lib.h>
#include <string.h>

/* Open, configure, and initialize an AAC encoder entirely from C.
   Returns 0 on success, or the FDK-AAC error code on failure.
   On success, *out_handle is set, and *out_frame_length / *out_max_out_bytes
   are filled from aacEncInfo. */
int fdkaac_open_and_init(HANDLE_AACENCODER *out_handle,
                         int sample_rate, int channels, int bitrate,
                         int aot, int transmux, int afterburner,
                         int *out_frame_length, int *out_max_out_bytes) {
    HANDLE_AACENCODER handle = NULL;
    AACENC_ERROR err;
    AACENC_InfoStruct info;

    err = aacEncOpen(&handle, 0, channels);
    if (err != AACENC_OK) return (int)err;

    if ((err = aacEncoder_SetParam(handle, AACENC_AOT, aot)) != AACENC_OK) goto fail;
    if ((err = aacEncoder_SetParam(handle, AACENC_SAMPLERATE, sample_rate)) != AACENC_OK) goto fail;
    if ((err = aacEncoder_SetParam(handle, AACENC_CHANNELMODE, channels == 1 ? MODE_1 : MODE_2)) != AACENC_OK) goto fail;
    if ((err = aacEncoder_SetParam(handle, AACENC_CHANNELORDER, 1)) != AACENC_OK) goto fail;
    if ((err = aacEncoder_SetParam(handle, AACENC_BITRATE, bitrate)) != AACENC_OK) goto fail;
    if ((err = aacEncoder_SetParam(handle, AACENC_TRANSMUX, transmux)) != AACENC_OK) goto fail;
    if ((err = aacEncoder_SetParam(handle, AACENC_AFTERBURNER, afterburner)) != AACENC_OK) goto fail;

    err = aacEncEncode(handle, NULL, NULL, NULL, NULL);
    if (err != AACENC_OK) goto fail;

    memset(&info, 0, sizeof(info));
    err = aacEncInfo(handle, &info);
    if (err != AACENC_OK) goto fail;

    *out_handle = handle;
    *out_frame_length = info.frameLength;
    *out_max_out_bytes = info.maxOutBufBytes;
    return 0;

fail:
    aacEncClose(&handle);
    return (int)err;
}

/* Encode PCM samples to AAC.
   pcm_buf: interleaved signed 16-bit PCM
   pcm_bytes: size of pcm_buf in bytes
   out_buf: output buffer for AAC data
   out_buf_size: size of out_buf in bytes
   out_bytes_written: set to actual bytes written on success
   Returns 0 on success, FDK-AAC error code on failure. */
int fdkaac_encode(HANDLE_AACENCODER handle,
                  void *pcm_buf, int pcm_bytes,
                  int num_samples,
                  void *out_buf, int out_buf_size,
                  int *out_bytes_written) {
    AACENC_BufDesc in_desc = {0}, out_desc = {0};
    AACENC_InArgs in_args = {0};
    AACENC_OutArgs out_args = {0};
    AACENC_ERROR err;

    void *in_ptr = pcm_buf;
    INT in_id = IN_AUDIO_DATA;
    INT in_size = pcm_bytes;
    INT in_el_size = sizeof(INT_PCM);

    in_desc.numBufs = 1;
    in_desc.bufs = &in_ptr;
    in_desc.bufferIdentifiers = &in_id;
    in_desc.bufSizes = &in_size;
    in_desc.bufElSizes = &in_el_size;

    void *out_ptr = out_buf;
    INT out_id = OUT_BITSTREAM_DATA;
    INT out_size = out_buf_size;
    INT out_el_size = 1;

    out_desc.numBufs = 1;
    out_desc.bufs = &out_ptr;
    out_desc.bufferIdentifiers = &out_id;
    out_desc.bufSizes = &out_size;
    out_desc.bufElSizes = &out_el_size;

    in_args.numInSamples = num_samples;
    in_args.numAncBytes = 0;

    err = aacEncEncode(handle, &in_desc, &out_desc, &in_args, &out_args);
    if (err != AACENC_OK) return (int)err;

    *out_bytes_written = out_args.numOutBytes;
    return 0;
}

/* Close an encoder handle. */
void fdkaac_close(HANDLE_AACENCODER *ph) {
    aacEncClose(ph);
}
