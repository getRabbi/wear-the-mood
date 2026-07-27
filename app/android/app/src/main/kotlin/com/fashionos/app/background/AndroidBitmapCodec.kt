package com.fashionos.app.background

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream

/**
 * `android.graphics` adapter for [BitmapCodec] (local BG §8.2).
 *
 * The only place the engine touches the Android imaging framework. Two properties
 * matter and are easy to get wrong:
 *
 *  * **No downscaling, ever.** The mask must match the uploaded original pixel for
 *    pixel or the backend rejects it. So no `inSampleSize`, no `inDensity` games —
 *    the bytes are already the ~1600px compressed JPEG.
 *  * **Straight (unpremultiplied) alpha.** `setPremultiplied(false)` before
 *    `setPixels` keeps a 50%-alpha edge at its true colour; premultiplied pixels
 *    would darken every soft edge in the PNG.
 *
 * PNG is lossless, so `compress(PNG, 100, …)` is bit-exact; the quality argument
 * is ignored by the PNG encoder.
 */
class AndroidBitmapCodec : BitmapCodec {

    override fun decode(bytes: ByteArray): DecodedImage {
        val options = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inScaled = false // never resample: dimensions must match the upload
            inMutable = false
        }
        var bitmap: Bitmap? = null
        try {
            bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                ?: throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "Could not decode the source image.",
                )
            val width = bitmap.width
            val height = bitmap.height
            if (width <= 0 || height <= 0) {
                throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "Source image has zero dimensions.",
                )
            }
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
            return DecodedImage(pixels, width, height)
        } catch (e: OutOfMemoryError) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Source image is too large to decode.",
                e,
            )
        } finally {
            bitmap?.recycle()
        }
    }

    override fun encodeMaskPng(alpha: ByteArray, width: Int, height: Int): ByteArray {
        // ALPHA_8 does not survive PNG encoding as a usable alpha channel on every
        // OEM, so the mask is written as an opaque GRAYSCALE image: value in R/G/B,
        // alpha 255. The backend's `decode_uploaded_mask` reduces any accepted mask
        // to a single channel, and takes luminance for an opaque image — which is
        // exactly the confidence value.
        val pixels = IntArray(width * height)
        for (i in pixels.indices) {
            val v = alpha[i].toInt() and 0xFF
            pixels[i] = (0xFF shl 24) or (v shl 16) or (v shl 8) or v
        }
        return encode(pixels, width, height, premultiplied = true)
    }

    override fun encodeCutoutPng(argb: IntArray, width: Int, height: Int): ByteArray =
        encode(argb, width, height, premultiplied = false)

    private fun encode(
        pixels: IntArray,
        width: Int,
        height: Int,
        premultiplied: Boolean,
    ): ByteArray {
        var bitmap: Bitmap? = null
        try {
            bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            if (!premultiplied) bitmap.setPremultiplied(false)
            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            val out = ByteArrayOutputStream(width * height / 4)
            // PNG is lossless; the quality argument is ignored by this encoder.
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)) {
                throw LocalCutoutException(
                    LocalCutoutErrors.INVALID_OUTPUT,
                    "PNG encoding failed.",
                )
            }
            return out.toByteArray()
        } catch (e: OutOfMemoryError) {
            throw LocalCutoutException(
                LocalCutoutErrors.INVALID_OUTPUT,
                "Ran out of memory encoding the output.",
                e,
            )
        } finally {
            bitmap?.recycle()
        }
    }
}
