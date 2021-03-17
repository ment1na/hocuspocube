import
    ../util/bitstruct, ../util/ioregs,
    dspstate,
    ../gecko/gecko, ../cycletiming,

    strformat, stew/endians2

template dspLog(msg: string): untyped =
    discard

#[
    DSP Init Sequence:
        Switching bit11 of DspCsr (here labeled as bootRom) from one to zero
        initialises an init sequence (it's status is indicated by bit 10 "busyCopying").
        It copies a payload of 1kb from Main RAM (at address 0x1000000) to the start of IRAM.
        This is as far as I know only used for the init ucode (as Dolphin calls it).
        It fulfills three tasks:
            - Reading out both the entire IROM and DROM. The read value is always
                discarded. Each load is proceeded by a nop. I assume this to be
                some kind of init sequence for the ROM, but couldn't test it.
                (Maybe this is what duddie is talking about? "This usually happens
                during boottime because DSP ROM is not enabled at cold reset and needs
                to be reenabled by small stub executed in IRAM. ")
            - Zero data RAM
            - Wait for any value to be received in it's mailbox and send back
                the value 0x00544348. The DSP is halted afterwards.

        Afterwards the program stored in the IROM is used to transfer programs to the DSP.
]#

makeBitStruct uint16, *DspCsr:
    reset[0] {.mutable.}: bool # resets the dsp, pc is set to the reset vector
    piint[1] {.mutable.}: bool # signals the program (in other sources processor, but program is more fitting imho)
    # interrupt to the DSP. Is cleared once it has been handled
    halt[2] {.mutable.}: bool
    aidint[3]: bool # AI DMA for transfering out of 
    aidintmsk[4] {.mutable.}: bool
    arint[5]: bool
    arintmsk[6] {.mutable.}: bool
    dspint[7]: bool
    dspintmsk[8] {.mutable.}: bool
    dspdma[9]: bool
    busyCopying[10]: bool
    bootRom[11] {.mutable.}: bool

makeBitStruct uint32, DspMailbox:
    data[0..30]: uint32
    status[31]: bool

    lo[0..15]: uint16
    hi[16..31]: uint16
    hiWrite[16..30]: uint16

type
    DspDmaDirection = enum
        dspDmaToAram
        dspDmaFromAram

makeBitStruct uint32, DspDmaCnt:
    direction[31]: DspDmaDirection
    length[0..30]: uint32

    hi[16..31]: uint16
    lo[0..15]: uint16

makeBitStruct uint32, DspDmaAdr:
    _[5..25] {.adr.}: uint32

makeBitStruct uint16, ArInfo:
    baseSize[0..2] {.mutable.}: uint32
    expansionSize[3..5] {.mutable.}: uint32
    unk[6] {.mutable.}: bool

type
    AuxFreq = enum
        auxFreq48Khz
        auxFreq32Khz
    DmaFreq = enum
        dmaFreq32Khz
        dmaFreq48Khz

makeBitStruct uint32, AiCr:
    pstat[0]: bool
    afr[1] {.mutable.}: AuxFreq
    aiintmsk[2] {.mutable.}: bool
    aiint[3]: bool
    aiintvld[4] {.mutable.}: bool
    scrreset[5]: bool
    dfr[6] {.mutable.}: DmaFreq

makeBitStruct uint32, AiVr:
    volL[0..7] {.mutable.}: uint32
    volR[8..15] {.mutable.}: uint32

type
    DspMainRamDmaDirection = enum
        dspDmaFromMain
        dspDmaToMainRam

    DspMem = enum
        dspMemDMem
        dspMemIMem

makeBitStruct uint16, DsCr:
    direction[0] {.mutable.}: DspMainRamDmaDirection
    dspMem[1] {.mutable.}: DspMem
    busy[2]: bool

makeBitStruct uint16, DsBl:
    _[2..15] {.len.}: uint16

makeBitStruct uint16, DspA:
    _[1..15] {.adr.}: uint16

makeBitStruct uint32, DsMa:
    _[2..25] {.adr.}: uint32

    _[2..15] {.loWrite.}: uint16
    lo[0..15]: uint16
    hi[16..25]: uint16

makeBitStruct uint16, AidLen:
    play[15] {.mutable.}: bool
    len[0..14] {.mutable.}: uint32

var
    mDspState*: DspState

    dspCsr*: DspCsr

    cmb: DspMailbox # CPU -> DSP
    dmb: DspMailbox # DSP -> CPU

    dsCr: DsCr
    dsbl: DsBl
    dspa: DspA
    dsma: DsMa

    arDmaCnt: DspDmaCnt
    arDmaMmAdr, arDmaArAdr: DspDmaAdr

    arInfo: ArInfo

    aidMAdr: DspDmaAdr
    aidLen: AidLen
    aidCntInit: uint16
    aidCntInitTimestamp: int64
    aidDoneEvent = InvalidEventToken

    aiCr: AiCr
    aiVr: AiVr

    aiSCntInit: uint32
    aiSCntInitTimestamp: int64
    aiIt: uint32

    aiItIntEvent = InvalidEventToken

    iram*: array[0x1000, uint16]
    irom*: array[0x1000, uint16]

    dram*: array[0x1000, uint16]
    drom*: array[0x800, uint16]

    aram*: array[0x1000000, uint8]

const
    SamplesPer32byte = 32 div (2*2)

    IRamStartAdr* = 0'u16
    IRomStartAdr* = 0x8000'u16

    DRamStartAdr* = 0'u16
    DRomStartAdr* = 0x1000'u16

dspCsr.halt = true

proc copySwapBytes16(dst: var openArray[uint16], src: openArray[uint16]) =
    assert dst.len == src.len
    for i in 0..<dst.len:
        dst[i] = fromBE src[i]

proc setupDspRom*(iromPath, dromPath: string) =
    echo &"reading DSP IROM from {iromPath} and DROM from {dromPath}"
    let
        iromLe = readFile(iromPath)
        dromLe = readFile(dromPath)
    copySwapBytes16(irom, toOpenArray(cast[ptr UncheckedArray[uint16]](unsafeAddr iromLe[0]), 0, irom.high))
    copySwapBytes16(drom, toOpenArray(cast[ptr UncheckedArray[uint16]](unsafeAddr dromLe[0]), 0, drom.high))

proc updateDspInt() =
    setExtInt extintDsp, 
        dspCsr.aidint and dspCsr.aidintmsk or
        dspCsr.arint and dspCsr.arintmsk or
        dspCsr.dspint and dspCsr.dspintmsk

proc updateAiInt() =
    setExtInt extintAi, aiCr.aiint and aiCr.aiintmsk

proc runPeripherals*() =
    if dspCsr.busyCopying:
        # copy 1kb payload
        dspLog "transfering inital dsp payload"
        copySwapBytes16(toOpenArray(iram, 0, 511), toOpenArray(cast[ptr UncheckedArray[uint16]](addr MainRAM[0x1000000]), 0, 511))
        dspCsr.busyCopying = false

# DSP side memory
proc instrRead*(adr: uint16): uint16 =
    case adr
    of IRamStartAdr..iram.len-1:
        iram[adr and uint16(iram.len - 1)]
    of IRomStartAdr..IRomStartAdr+uint16(irom.len)-1:
        irom[adr and uint16(irom.len - 1)]
    else:
        echo &"unknown dsp instr read {adr:04X} from {mDspState.pc:04X}"
        0'u16

proc instrWrite*(adr, val: uint16) =
    if adr < IRomStartAdr:
        iram[adr and uint16(iram.len - 1)] = val
    else:
        echo &"unknown dsp instr write {adr:04X} {`val`:X} from {mDspState.pc:04X}"

proc dataRead*(adr: uint16): uint16 =
    case adr:
    of DRamStartAdr..DRamStartAdr+uint16(dram.len)-1:
        dram[adr and uint16(dram.len - 1)]
    of DRomStartAdr..DRomStartAdr+uint16(drom.len-1):
        drom[adr and uint16(drom.len - 1)]
    else:
        case adr
        of 0xFFC9: uint16 dsCr
        of 0xFFCB: uint16 dsbl
        of 0xFFCD: uint16 dspa
        of 0xFFCE: dsma.hi
        of 0xFFCF: dsma.lo

        of 0xFFFC: dmb.hi
        of 0xFFFD: dmb.lo
        of 0xFFFE: cmb.hi
        of 0xFFFF: dspLog &"dsp: reading cmb lo status {cmb.status}"; cmb.status = false; cmb.lo
        else: echo &"unknown dsp data read {adr:X} from {mDspState.pc:04X}"; 0'u16

proc dataWrite*(adr, val: uint16) =
    case adr:
    of DRamStartAdr..DRamStartAdr+uint16(dram.len)-1:
        dram[adr and uint16(dram.len - 1)] = val
    of DRomStartAdr..DRomStartAdr+uint16(drom.len-1):
        drom[adr and uint16(drom.len - 1)] = val
    else:
        case adr
        of 0xFFC9: dsCr.mutable = val
        of 0xFFCB:
            dsbl.len = val

            dspLog &"dsp Main RAM DMA len: {dsbl.len:04X} MM adr: {dsma.adr:08X} DSP adr {dspa.adr:04X} {dsCr.dspMem} {dsCr.direction}"

            var
                src = cast[ptr UncheckedArray[uint16]](addr MainRAM[dsma.adr])
                dst = cast[ptr UncheckedArray[uint16]](case dsCr.dspMem
                    of dspMemIMem: addr iram[dspa.adr]
                    of dspMemDMem: addr dram[dspa.adr])

            if dsCr.direction == dspDmaToMainRam:
                swap src, dst

            copySwapBytes16(toOpenArray(dst, 0, int(dsbl.len div 2) - 1), toOpenArray(src, 0, int(dsbl.len div 2) - 1))
        of 0xFFCD: dspa.adr = val
        of 0xFFCE: dsma.hi = val
        of 0xFFCF: dsma.loWrite = val

        of 0xFFFB:
            if (val and 1) != 0:
                echo "cpu interrupt triggered by dsp"
                dspCsr.dspint = true
                updateDspInt()

        of 0xFFFC: dspLog "dsp: writing dmb hi"; dmb.hiWrite = val
        of 0xFFFD: dspLog &"dsp: writing dmb lo status {dmb.status}"; dmb.status = true; dmb.lo = val
        else: echo &"unknown dsp data write {adr:04X} {`val`:X} from {mDspState.pc:04X}"

proc doDspDma(mmPtr: ptr UncheckedArray[byte], transferLines: uint32,
    direction: static[DspDmaDirection],
    aramSize: uint32, aramSizeSimple: static[int]) =

    let (maskLo, maskHi) = if aramSizeSimple < 0: (0x1FF'u32, 0xFF800000'u32)
        elif aramSize > 0: (0x3FFFFF'u32, 0xFF800000'u32)
        else: (0xFFFFFFFF'u32, 0'u32)

    for i in 0..<transferLines:
        let offset = uint32(i) shl 5

        if offset < aramSize*1024*1024:
            if direction == dspDmaFromAram:
                zeroMem(addr mmPtr[offset], 32)
        else:
            let
                hi = offset and maskHi
                aramAdr = (offset and maskLo) or
                    (if aramSizeSimple < 0: hi shl 1
                        elif aramSizeSimple > 0: hi shr 1
                        else: 0'u32)

            case direction
            of dspDmaFromAram:
                copyMem(addr mmPtr[offset], addr aram[aramAdr], 32)
            of dspDmaToAram:
                copyMem(addr aram[aramAdr], addr mmPtr[offset], 32)

proc curAiSCnt(): uint32 =
    if aiCr.pstat:
        result = uint32((geckoTimestamp - aiSCntInitTimestamp) div geckoCyclesPerAiSample) + aiSCntInit
        #dspLog "current samples ", result, " timestamp: ", geckoTimestamp, " ", aiSCntInitTimestamp
    else:
        result = aiSCntInit

proc curAidCnt(): uint16 =
    let blocksPast = uint16((geckoTimestamp - aidCntInitTimestamp) div ((case aiCr.dfr
                    of dmaFreq32Khz: geckoCyclesPerSecond div 32_000
                    of dmaFreq48Khz: geckoCyclesPerSecond div 48_000) * SamplesPer32byte))
    if blocksPast > aidCntInit:
        0'u16
    else:
        aidCntInit - blocksPast

proc startAid(timestamp: int64) =
    if aidCntInit > 0:
        let cycles = int64(aidCntInit * 32 div (2*2)) *
            (case aiCr.dfr
                of dmaFreq32Khz: geckoCyclesPerSecond div 32_000
                of dmaFreq48Khz: geckoCyclesPerSecond div 48_000)
        dspLog &"playing {aidLen.len * 32 div (2*2)} stereo samples"
        aidDoneEvent = scheduleEvent(timestamp + cycles, 0, proc(timestamp: int64) =
            aidCntInitTimestamp = timestamp
            if aidLen.play:
                aidCntInit = uint16 aidLen.len
            else:
                aidCntInit = 0
            startAid(timestamp)
            dspCsr.aidint = true
            updateDspInt())

proc rescheduleAi(timestamp: int64) =
    if aiItIntEvent != InvalidEventToken:
        cancelEvent aiItIntEvent

    let curSample = curAiSCnt()
    # TODO: what about overflow?
    if aiCr.pstat and not aiCr.aiintvld and curSample <= aiIt:
        aiItIntEvent = scheduleEvent(timestamp + geckoCyclesPerAiSample * int64(curSample - aiIt), 0,
            proc(timestamp: int64) =
                aiItIntEvent = InvalidEventToken
                aiCr.aiint = true
                updateAiInt())

# cpu side memory
ioBlock dsp, 0x200:
of cmbh, 0x00, 2:
    read: cmb.hi
    write: dspLog &"cpu: writing cmb hi {cmb.status}"; cmb.hiWrite = val
of cmbl, 0x02, 2:
    read: cmb.lo
    write: dspLog &"cpu: writing cmb lo {cmb.status}"; cmb.lo = val; cmb.status = true
of dmbh, 0x04, 2:
    read: dmb.hi
of dmbl, 0x06, 2:
    read: dspLog &"cpu: reading dmb lo {dmb.status}"; dmb.status = false; dmb.lo
of dspcr, 0x0A, 2:
    read: uint16(dspCsr)
    write:
        let val = DspCsr(val)

        # apparently only changing this bit sets the pc
        if dspCsr.bootRom and not val.bootRom:
            dspCsr.busyCopying = true
            dspLog "resetting to iram reset vector"
            mDspState.pc = IRamStartAdr

        dspCsr.mutable = val.mutable

        if val.aidint: dspCsr.aidint = false
        if val.arint: dspCsr.arint = false
        if val.dspint: dspCsr.dspint = false
        updateDspInt()

of arInfo, 0x12, 2:
    read: uint16 arInfo
    write: arInfo.mutable = val
of arMode, 0x16, 2:
    read: 1'u16 # indicates that ARAM has finished initialising

of arDmaMmAddr, 0x20, 4:
    read: uint32 arDmaMmAdr
    write: arDmaMmAdr.adr = val
of arDmaArAddr, 0x24, 4:
    read: uint32 arDmaArAdr
    write: arDmaArAdr.adr = val
of arDmaCntHi, 0x28, 2:
    read: arDmaCnt.hi
    write: arDmaCnt.hi = val
of arDmaCntLo, 0x2A, 2:
    read: arDmaCnt.lo
    write:
        arDmaCnt.lo = val

        dspLog &"ARAM DMA MM Adr: {arDmaMmAdr.adr:08X} aram: {arDmaArAdr.adr:08X} len {arDmaCnt.length} direction: {arDmaCnt.direction}"

        # based on https://github.com/dolphin-emu/dolphin/pull/7740
        let
            transferLines = min(arDmaCnt.length shr 5, 16)
            aramSize = min(2'u32 shl arInfo.baseSize, 32) # in MB
            mmPtr = cast[ptr UncheckedArray[byte]](addr MainRAM[arDmaMmAdr.adr])

        template doDma(dir: DspDmaDirection): untyped =
            if aramSize < 16:
                doDspDma(mmPtr, transferLines, dir, aramSize, -1)
            elif aramSize > 16:
                doDspDma(mmPtr, transferLines, dir, aramSize, 1)
            else:
                doDspDma(mmPtr, transferLines, dir, aramSize, 0)

        case arDmaCnt.direction:
        of dspDmaToAram: doDma(dspDmaToAram)
        of dspDmaFromAram: doDma(dspDmaFromAram)

        dspCsr.arint = true

        updateDspInt()

of aidMAdr, 0x30, 4:
    read: uint32 aidMAdr
    write:
        aidMAdr.adr = val
of aidLen, 0x36, 2:
    read: uint16 aidLen
    write:
        aidLen.mutable = val
        dspLog &"writing aidlen {aidLen.play} {aidLen.len}"
        if aidCntInit == 0 and aidLen.play:
            aidCntInit = uint16 aidLen.len
            startAid(geckoTimestamp)
of aidCnt, 0x3A, 2:
    read: curAidCnt()

ioBlock ai, 0x20:
of aiCr, 0x0, 4:
    read: uint32 aiCr
    write:
        dspLog &"writing ai cr {val:08X} {uint32(aiCr):08X} {geckoState.pc:08X}"

        aiCr.mutable = val
        let val = AiCr val

        if val.pstat and not aiCr.pstat:
            aiSCntInitTimestamp = geckoTimestamp
            aiCr.pstat = true
            dspLog &"started playing! at timestamp {geckoTimestamp}"
        if not val.pstat and aiCr.pstat:
            aiSCntInit = curAiSCnt()
            aiCr.pstat = false
            dspLog "stop playing"

        if val.scrreset:
            aiSCntInit = 0
            dspLog &"resetting to timestamp {geckoTimestamp}"
            aiSCntInitTimestamp = geckoTimestamp

        if val.aiint:
            aiCr.aiint = false

        updateAiInt()
        rescheduleAi(geckoTimestamp)
of aiVr, 0x4, 4:
    read: uint32 aiVr
of aiSCnt, 0x8, 4:
    read:
        let samples = curAiSCnt()
        #dspLog "read sample counter ", samples
        samples
of aiIt, 0xC, 4:
    read: aiIt
    write:
        aiIt = val