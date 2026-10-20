package com.bdkaudio.bdk_audio

private class TextConfig(private val value: String) {
    override fun toString() = value
}

class GetterConfig {
    fun getCodecType() = 4
    fun getSampleRate() = 0x20
    fun getBitsPerSample() = 2
    fun getChannelMode() = 2
    fun getCodecSpecific1() = 1001L
    fun getCodecSpecific2() = Long.MIN_VALUE
    fun getCodecSpecific3() = -9L
    fun getCodecSpecific4() = Long.MAX_VALUE
    override fun toString() = "codecType:0,codecName:LDAC,sampleRate:0,bitsPerSample:0,channelMode:0,codecSpecific1:0,codecSpecific2:0,codecSpecific3:0,codecSpecific4:0"
}

/** Standalone JVM tests: real parsing/validation/cache code, no Android runtime. */
fun main() {
    var passed = 0
    fun test(name: String, body: () -> Unit) {
        try { body(); passed++; println("PASS $name") }
        catch (error: Throwable) { throw AssertionError("FAIL $name", error) }
    }
    val ldac = CodecConfigMap(4, "LDAC", 1, 2, 2, 1001, Long.MIN_VALUE, -9, Long.MAX_VALUE)
    fun rejected(action: () -> Unit) {
        var thrown = false
        try { action() } catch (_: IllegalArgumentException) { thrown = true }
        check(thrown) { "Unsupported configuration was accepted" }
    }
    test("public getters are authoritative and all four long fields survive") {
        val parsed = checkNotNull(CodecWire.parse(GetterConfig()))
        check(parsed.sampleRateMask == 0x20)
        check(parsed.cs2 == Long.MIN_VALUE && parsed.cs3 == -9L && parsed.cs4 == Long.MAX_VALUE)
        check(parsed.toMap()["cs4"] == Long.MAX_VALUE)
    }
    test("source toString masks and signed hexadecimal long fields parse") {
        val parsed = checkNotNull(CodecWire.parse(TextConfig(
            "{codecName:LDAC,mCodecType:4,mSampleRate:0x3(44100|48000),mBitsPerSample:0x2,mChannelMode:0x2,mCodecSpecific1:1002,mCodecSpecific2:0xffffffffffffffff,mCodecSpecific3:-9,mCodecSpecific4:9223372036854775807}")))
        check(parsed.sampleRateMask == 3 && parsed.cs2 == -1L && parsed.cs3 == -9L)
    }
    test("missing fields never become invented zero capabilities") {
        check(CodecWire.parse(TextConfig("codecType:4,sampleRate:1,bitsPerSample:2,channelMode:2,codecSpecific1:1000")) == null)
        check(CodecWire.parse(TextConfig("codecType:4,sampleRate:garbage")) == null)
    }
    test("ambiguous or unrelated audio devices require explicit selection") {
        check(CodecWire.selectDevice(listOf("AA" to "Headphones"), null) == null)
        check(CodecWire.selectDevice(listOf("AA" to "BDK SPEAKER"), null) == "AA")
        check(CodecWire.selectDevice(listOf("AA" to "BDK SPEAKER", "BB" to "BDK SECOND"), null) == null)
        check(CodecWire.selectDevice(listOf("AA" to "Speaker"), "aa") == "AA")
        check(CodecWire.selectDevice(listOf("AA" to "Speaker"), "BB") == null)
    }
    test("apply rejects auto, multibit and unavailable codec combinations") {
        val caps = listOf(ldac.copy(sampleRateMask = 3, bitsMask = 3))
        CodecWire.validate(ldac, caps, ldac)
        rejected { CodecWire.validate(ldac.copy(sampleRateMask = 0), caps, ldac) }
        rejected { CodecWire.validate(ldac.copy(sampleRateMask = 3), caps, ldac) }
        rejected { CodecWire.validate(ldac.copy(sampleRateMask = 8), caps, ldac) }
        rejected { CodecWire.validate(ldac.copy(codecType = 2), caps, ldac) }
        rejected { CodecWire.validate(ldac.copy(channelMask = 1), caps, ldac) }
        rejected { CodecWire.validate(ldac, emptyList(), ldac) }
    }
    test("integer channel fields reject fractional and overflow values") {
        check(CodecWire.requestedLong(Long.MIN_VALUE, "cs2") == Long.MIN_VALUE)
        rejected { CodecWire.requestedInt(2.5, "bitsMask") }
        rejected { CodecWire.requestedInt(Long.MAX_VALUE, "codecType") }
        rejected { CodecWire.requestedLong(null, "cs1") }
    }
    test("unrecognized LDAC quality codes are not accepted as quality requests") {
        rejected { CodecWire.validate(ldac.copy(cs1 = 1009), listOf(ldac), ldac) }
    }
    test("quality changes require active LDAC while opaque vendor fields stay unchanged") {
        val caps = listOf(ldac.copy(sampleRateMask = 3, bitsMask = 3))
        check(CodecWire.ldacQualityCodes(ldac, caps) == listOf(1000L, 1001L, 1002L, 1003L))
        for (quality in 1000L..1003L) CodecWire.validate(ldac.copy(cs1 = quality), caps, ldac)
        rejected { CodecWire.validate(ldac.copy(cs2 = 0), caps, ldac) }
        rejected { CodecWire.validate(ldac.copy(cs3 = 0), caps, ldac) }
        rejected { CodecWire.validate(ldac.copy(cs1 = 1000), caps, ldac.copy(cs1 = 1009)) }
        rejected { CodecWire.validate(ldac.copy(cs1 = 1000), caps, ldac.copy(codecType = 11)) }
        val vendor = ldac.copy(codecType = 11, codecName = "LHDC", cs1 = 0x4c484443)
        CodecWire.validate(vendor, listOf(vendor), vendor)
        rejected { CodecWire.validate(vendor.copy(cs1 = 1000), listOf(vendor), vendor) }
        check(CodecWire.ldacQualityCodes(vendor, listOf(vendor)).isEmpty())
        check(CodecWire.ldacQualityCodes(ldac.copy(sampleRateMask = 3), caps).isEmpty())
    }
    test("default LDAC accepts explicit canonical quality and preserves opaque fields") {
        val active = ldac.copy(cs1 = 0)
        val caps = listOf(ldac.copy(sampleRateMask = 3, bitsMask = 3))
        check(CodecWire.ldacQualityCodes(active, caps) == listOf(1000L, 1001L, 1002L, 1003L))
        for (quality in 1000L..1003L) CodecWire.validate(ldac.copy(cs1 = quality), caps, active)
        rejected { CodecWire.validate(ldac.copy(cs1 = 1000, cs2 = 0), caps, active) }
        rejected { CodecWire.validate(ldac.copy(cs1 = 1000, cs3 = 0), caps, active) }
        rejected { CodecWire.validate(ldac.copy(cs1 = 1000, cs4 = 0), caps, active) }
        rejected { CodecWire.validate(ldac.copy(cs1 = 1009), caps, active) }
    }
    test("probed LHDC V5 allows only quality low-byte mutations with opaque fields preserved") {
        val active = CodecConfigMap(15, "LHDC V5", 32, 2, 2, 0x100008008L, -7L, 0x5c000006L, -9L)
        val caps = listOf(active.copy(sampleRateMask = 43, bitsMask = 3, cs1 = 0, cs2 = 0, cs3 = 0, cs4 = 0))
        for (index in 3L..9L) CodecWire.validate(active.copy(cs1 = 0x100008000L or index), caps, active)
        CodecWire.validate(active.copy(codecName = "Requested", cs1 = 0x100008006L), caps, active)
        for (index in 0L..2L) rejected { CodecWire.validate(active.copy(cs1 = 0x100008000L or index), caps, active) }
        rejected { CodecWire.validate(active.copy(cs1 = 0x8006), caps, active) }
        rejected { CodecWire.validate(active.copy(cs1 = 0x100008006L, cs2 = 0), caps, active) }
        rejected { CodecWire.validate(active.copy(cs1 = 0x100008006L, cs3 = 0x5c000000), caps, active) }
        rejected { CodecWire.validate(active.copy(cs1 = 0x100008006L, cs4 = 0), caps, active) }
        rejected { CodecWire.validate(active.copy(cs1 = 0x10000800aL), caps, active) }
        for (rate in listOf(1, 2)) {
            val lowRate = active.copy(sampleRateMask = rate)
            for (index in 0L..7L) CodecWire.validate(lowRate.copy(cs1 = 0x100008000L or index), caps, lowRate)
            rejected { CodecWire.validate(lowRate.copy(cs1 = 0x100008008L), caps, lowRate.copy(cs1 = 0x100008007L)) }
        }
        for (bad in listOf(active.copy(codecName = "LHDC"), active.copy(cs3 = 0x4c000006), active.copy(cs1 = 0xc008))) {
            rejected { CodecWire.validate(bad.copy(cs1 = 0x8006), caps, bad) }
        }
        val lossless = active.copy(cs1 = 0x8009, cs3 = 0x5c000080)
        CodecWire.validate(lossless, caps, lossless)
        rejected { CodecWire.validate(lossless.copy(cs1 = 0x8006), caps, lossless) }
    }
    test("known LHDC tuple rejects invalid rate-only or lossless requests even with unchanged quality bits") {
        val active = CodecConfigMap(15, "LHDC V5", 32, 2, 2, 0x8008, 0, 0x5c000000, 0)
        val caps = listOf(active.copy(sampleRateMask = 43, bitsMask = 3, cs1 = 0, cs3 = 0))
        rejected { CodecWire.validate(active.copy(sampleRateMask = 2), caps, active) }
        CodecWire.validate(active.copy(sampleRateMask = 2, cs1 = 0x8007), caps, active)
        val lossless = active.copy(cs3 = 0x5c000080)
        rejected { CodecWire.validate(lossless.copy(sampleRateMask = 2), caps, lossless) }
        CodecWire.validate(lossless.copy(sampleRateMask = 2, cs1 = 0x8009), caps, lossless)
    }
    test("queued pre-apply broadcasts cannot repopulate invalidated cache") {
        val cache = CodecStatusCache()
        val old = ObservedCodecStatus(ldac, listOf(ldac), 100_000, 10_000)
        cache.invalidateBefore("AA", 10_100)
        cache.put("AA", 2, old) // Delivered to the worker after submission.
        check(cache.get("AA", 2, 10_200) == null)
        val current = old.copy(elapsedMs = 10_101, observedAtMs = 100_101)
        cache.put("AA", 2, current)
        check(cache.get("AA", 2, 10_200) == current)
    }
    test("broadcast cache is tied to device, connection epoch and freshness") {
        val cache = CodecStatusCache()
        val observation = ObservedCodecStatus(ldac, listOf(ldac), 100_000, 10_000)
        cache.put("AA", 2, observation)
        check(cache.get("aa", 2, 10_500) == observation)
        check(cache.get("BB", 2, 10_500) == null)
        check(cache.get("AA", 3, 10_500) == null)
        check(cache.get("AA", 2, 15_001) == null)
        check(cache.get("AA", 2, 9_999) == null)
        cache.remove("AA")
        check(cache.get("AA", 2, 10_500) == null)
    }
    println("$passed native codec tests passed")
}
