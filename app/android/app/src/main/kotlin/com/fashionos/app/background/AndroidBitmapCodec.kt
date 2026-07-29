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
        // The confidence goes in the ALPHA channel, and is mirrored into R/G/B.
        //
        // This mirroring is not belt-and-braces decoration — it is the contract.
        // `compress(PNG)` on an ARGB_8888 bitmap always emits an **RGBA** PNG, even
        // when every alpha byte is 0xFF, and the backend's `_extract_mask_channel`
        // tests alpha-bearing modes FIRST:
        //
        //     if img.mode in ("RGBA", "LA", "PA"): return img.getchannel("A")
        //
        // so the luminance branch is unreachable for anything this encoder produces.
        // Writing the value into R/G/B with `alpha = 0xFF` (as this did until the
        // 2026-07-29 device diagnostic) therefore handed the server a uniformly
        // opaque band: mean coverage 1.0, tripped `_MAX_LOCAL_ALPHA_AREA` (0.998),
        // and EVERY ingest came back 422 "The cutout mask does not look usable."
        // Putting it in alpha as well makes both server branches correct.
        //
        // Unpremultiplied: with RGB mirroring alpha, premultiplication would square
        // the value (v * v / 255) and darken every soft edge.
        return encode(packMaskPixels(alpha, width, height), width, height, premultiplied = false)
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

/**
 * Pack an 8-bit confidence mask into ARGB pixels: value in **alpha** and mirrored
 * into R/G/B (see [AndroidBitmapCodec.encodeMaskPng] for why both are required).
 *
 * Deliberately a pure top-level function rather than an inline loop, so a JVM unit
 * test can pin the channel contract without `android.graphics`. The bug this guards
 * against shipped past 83 green Android tests precisely because the only coverage of
 * `encodeMaskPng` was a fake that never packed anything.
 */
internal fun packMaskPixels(alpha: ByteArray, width: Int, height: Int): IntArray {
    require(width > 0 && height > 0) { "mask dimensions must be positive" }
    require(alpha.size >= width * height) { "alpha is shorter than the mask" }
    val pixels = IntArray(width * height)
    for (i in pixels.indices) {
        val v = alpha[i].toInt() and 0xFF
        pixels[i] = (v shl 24) or (v shl 16) or (v shl 8) or v
    }
    return pixels
}
