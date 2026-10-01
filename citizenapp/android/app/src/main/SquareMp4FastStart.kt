package com.crcfrcn.citizenapp

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 把普通 MP4 的 moov 移到首个 mdat 前，并同步修正 stco/co64 数据偏移。
 *
 * 只接受 Media3 生成的单 mdat 非分片 MP4；遇到未知或越界结构立即失败，不猜测修复。
 */
object SquareMp4FastStart {
    private const val MAX_MOOV_BYTES = 64L * 1024 * 1024

    data class Atom(val offset: Long, val size: Long, val headerSize: Int, val type: String)

    fun optimize(file: File) {
        val atoms = topLevelAtoms(file)
        val moov = atoms.singleOrNull { it.type == "moov" }
            ?: throw IllegalArgumentException("MP4 缺少唯一 moov")
        val mdat = atoms.singleOrNull { it.type == "mdat" }
            ?: throw IllegalArgumentException("MP4 缺少唯一 mdat")
        if (moov.offset < mdat.offset) return
        require(moov.size <= MAX_MOOV_BYTES) { "MP4 moov 过大" }

        val prefix = atoms.filter { it.offset < mdat.offset && it.type != "moov" }
        val newMdatOffset = prefix.sumOf { it.size } + moov.size
        val delta = (newMdatOffset + mdat.headerSize) - (mdat.offset + mdat.headerSize)
        val moovBytes = RandomAccessFile(file, "r").use { input ->
            input.seek(moov.offset)
            ByteArray(moov.size.toInt()).also(input::readFully)
        }
        patchChunkOffsets(moovBytes, delta)

        val temporary = File(file.parentFile, "${file.name}.faststart")
        RandomAccessFile(file, "r").use { input ->
            RandomAccessFile(temporary, "rw").use { output ->
                output.setLength(0)
                for (atom in atoms) {
                    if (atom.offset >= mdat.offset || atom.type == "moov") continue
                    copyAtom(input, output, atom)
                }
                output.write(moovBytes)
                for (atom in atoms) {
                    if (atom.offset < mdat.offset || atom.type == "moov") continue
                    copyAtom(input, output, atom)
                }
            }
        }
        require(temporary.length() == file.length()) { "MP4 faststart 重写长度不一致" }
        if (!file.delete() || !temporary.renameTo(file)) {
            temporary.delete()
            throw IllegalStateException("MP4 faststart 原子替换失败")
        }
        require(isFastStart(file)) { "MP4 faststart 校验失败" }
    }

    fun isFastStart(file: File): Boolean {
        val atoms = topLevelAtoms(file)
        val moov = atoms.indexOfFirst { it.type == "moov" }
        val mdat = atoms.indexOfFirst { it.type == "mdat" }
        return moov >= 0 && mdat >= 0 && moov < mdat
    }

    fun containsSampleEntry(file: File, entry: String): Boolean {
        require(entry.length == 4)
        val atom = topLevelAtoms(file).singleOrNull { it.type == "moov" } ?: return false
        if (atom.size > MAX_MOOV_BYTES) return false
        val needle = entry.toByteArray(Charsets.US_ASCII)
        val bytes = RandomAccessFile(file, "r").use { input ->
            input.seek(atom.offset)
            ByteArray(atom.size.toInt()).also(input::readFully)
        }
        return bytes.indices.any { index ->
            index + needle.size <= bytes.size &&
                needle.indices.all { bytes[index + it] == needle[it] }
        }
    }

    fun topLevelAtoms(file: File): List<Atom> = RandomAccessFile(file, "r").use { input ->
        val atoms = mutableListOf<Atom>()
        var offset = 0L
        while (offset < input.length()) {
            input.seek(offset)
            val size32 = input.readInt().toLong() and 0xffff_ffffL
            val typeBytes = ByteArray(4).also(input::readFully)
            val type = typeBytes.toString(Charsets.US_ASCII)
            val headerSize = if (size32 == 1L) 16 else 8
            val size = when (size32) {
                0L -> input.length() - offset
                1L -> input.readLong()
                else -> size32
            }
            require(size >= headerSize && offset + size <= input.length()) { "MP4 atom 越界" }
            atoms += Atom(offset, size, headerSize, type)
            offset += size
        }
        require(offset == input.length()) { "MP4 atom 未覆盖完整文件" }
        atoms
    }

    private fun patchChunkOffsets(moov: ByteArray, delta: Long) {
        patchBoxes(moov, 8, moov.size, delta)
    }

    private fun patchBoxes(bytes: ByteArray, start: Int, end: Int, delta: Long) {
        var offset = start
        while (offset + 8 <= end) {
            val size32 = uint32(bytes, offset)
            val header = if (size32 == 1L) 16 else 8
            val size = if (size32 == 1L) int64(bytes, offset + 8) else size32
            if (size < header || offset + size > end) return
            val type = String(bytes, offset + 4, 4, Charsets.US_ASCII)
            when (type) {
                "stco" -> patchStco(bytes, offset + header, (offset + size).toInt(), delta)
                "co64" -> patchCo64(bytes, offset + header, (offset + size).toInt(), delta)
                "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "udta", "meta" -> {
                    val childStart = offset + header + if (type == "meta") 4 else 0
                    patchBoxes(bytes, childStart, (offset + size).toInt(), delta)
                }
            }
            offset += size.toInt()
        }
    }

    private fun patchStco(bytes: ByteArray, start: Int, end: Int, delta: Long) {
        require(start + 8 <= end) { "stco 头越界" }
        val count = uint32(bytes, start + 4).toInt()
        require(start + 8L + count * 4L <= end) { "stco 条目越界" }
        for (index in 0 until count) {
            val position = start + 8 + index * 4
            val value = uint32(bytes, position) + delta
            require(value in 0..0xffff_ffffL) { "stco 偏移溢出" }
            ByteBuffer.wrap(bytes, position, 4).order(ByteOrder.BIG_ENDIAN).putInt(value.toInt())
        }
    }

    private fun patchCo64(bytes: ByteArray, start: Int, end: Int, delta: Long) {
        require(start + 8 <= end) { "co64 头越界" }
        val count = uint32(bytes, start + 4).toInt()
        require(start + 8L + count * 8L <= end) { "co64 条目越界" }
        for (index in 0 until count) {
            val position = start + 8 + index * 8
            val value = int64(bytes, position) + delta
            require(value >= 0) { "co64 偏移溢出" }
            ByteBuffer.wrap(bytes, position, 8).order(ByteOrder.BIG_ENDIAN).putLong(value)
        }
    }

    private fun copyAtom(input: RandomAccessFile, output: RandomAccessFile, atom: Atom) {
        input.seek(atom.offset)
        var remaining = atom.size
        val buffer = ByteArray(1024 * 1024)
        while (remaining > 0) {
            val count = input.read(buffer, 0, minOf(buffer.size.toLong(), remaining).toInt())
            require(count > 0) { "MP4 atom 复制提前结束" }
            output.write(buffer, 0, count)
            remaining -= count
        }
    }

    private fun uint32(bytes: ByteArray, offset: Int): Long =
        ByteBuffer.wrap(bytes, offset, 4).order(ByteOrder.BIG_ENDIAN).int.toLong() and 0xffff_ffffL

    private fun int64(bytes: ByteArray, offset: Int): Long =
        ByteBuffer.wrap(bytes, offset, 8).order(ByteOrder.BIG_ENDIAN).long
}
