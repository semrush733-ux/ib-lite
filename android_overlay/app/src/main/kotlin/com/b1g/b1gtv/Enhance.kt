package com.b1g.b1gtv

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.Effect
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.Contrast
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import androidx.media3.effect.HslAdjustment

/**
 * "Picture Enhance": a light contrast-adaptive sharpen (the idea of AMD's CAS) plus a small
 * colour and contrast lift. Level 1 = low, 2 = high. It makes the picture look crisper; it does
 * not add detail the stream does not carry.
 */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
object Enhance {
    fun effects(level: Int): List<Effect> = when {
        level >= 2 -> listOf(SharpenEffect(0.75f), Contrast(0.06f), HslAdjustment.Builder().adjustSaturation(9f).build())
        level == 1 -> listOf(SharpenEffect(0.4f), Contrast(0.03f), HslAdjustment.Builder().adjustSaturation(5f).build())
        else -> emptyList()
    }
}

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class SharpenEffect(private val amount: Float) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram =
        SharpenProgram(useHdr, amount)
}

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
private class SharpenProgram(useHdr: Boolean, private val amount: Float) :
    BaseGlShaderProgram(useHdr, 1) {

    private val program = GlProgram(VERTEX, FRAGMENT)
    private var texel = floatArrayOf(0f, 0f)

    init {
        program.setBufferAttribute(
            "aFramePosition",
            GlUtil.getNormalizedCoordinateBounds(),
            GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE,
        )
    }

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        texel = floatArrayOf(1f / inputWidth.coerceAtLeast(1), 1f / inputHeight.coerceAtLeast(1))
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        program.use()
        program.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
        program.setFloatsUniform("uTexel", texel)
        program.setFloatUniform("uSharp", amount)
        program.bindAttributesAndUniforms()
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    override fun release() {
        super.release()
        try {
            program.delete()
        } catch (_: Exception) {
        }
    }

    companion object {
        const val VERTEX = """
attribute vec4 aFramePosition;
varying vec2 vTexSamplingCoord;
void main() {
  gl_Position = aFramePosition;
  vTexSamplingCoord = vec2(aFramePosition.x * 0.5 + 0.5, aFramePosition.y * 0.5 + 0.5);
}
"""
        // Contrast-adaptive sharpening on the 4 neighbours: strong on soft edges, gentle where
        // the picture is already contrasty, so no halos and no noise boost on flat areas.
        const val FRAGMENT = """
precision mediump float;
uniform sampler2D uTexSampler;
uniform vec2 uTexel;
uniform float uSharp;
varying vec2 vTexSamplingCoord;
void main() {
  vec2 p = vTexSamplingCoord;
  vec4 e4 = texture2D(uTexSampler, p);
  vec3 e = e4.rgb;
  vec3 b = texture2D(uTexSampler, p + vec2(0.0, -uTexel.y)).rgb;
  vec3 d = texture2D(uTexSampler, p + vec2(-uTexel.x, 0.0)).rgb;
  vec3 f = texture2D(uTexSampler, p + vec2(uTexel.x, 0.0)).rgb;
  vec3 h = texture2D(uTexSampler, p + vec2(0.0, uTexel.y)).rgb;
  vec3 mn = min(min(min(d, e), min(f, b)), h);
  vec3 mx = max(max(max(d, e), max(f, b)), h);
  vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, 0.0001), 0.0, 1.0));
  vec3 w = -amp / mix(8.0, 5.0, uSharp);
  vec3 c = (b * w + d * w + f * w + h * w + e) / (1.0 + 4.0 * w);
  gl_FragColor = vec4(clamp(c, 0.0, 1.0), e4.a);
}
"""
    }
}
