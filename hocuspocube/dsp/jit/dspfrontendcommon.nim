import
    strformat,
    ../../util/jit/ir,
    ".."/[dsp, dspstate],
    ../../cycletiming

type
    DspIrState* = object
        pc*, instr*: uint16
        cycles*: int32
        branch*: bool
    
    DspStatusBit* = enum
        dspStatusBitCa
        dspStatusBitOv
        dspStatusBitZr
        dspStatusBitMi
        dspStatusBitExt
        dspStatusBitUnnorm
        dspStatusBitTb
        dspStatusBitSv
        dspStatusBitTe0
        dspStatusBitTe1
        dspStatusBitTe2
        dspStatusBitTe3
        dspStatusBitEt
        dspStatusBitIm
        dspStatusBitXl
        dspStatusBitDp

using builder: var IrBlockBuilder[DspIrState]

proc signExt40(builder; val: IrInstrRef): IrInstrRef =
    builder.biop(asrX, builder.biop(lslX, val, builder.imm(24)), builder.imm(24))

proc fetchFollowingImm*(builder): uint16 =
    builder.regs.pc += 1
    builder.regs.cycles += int32 gekkoCyclesPerDspCycle
    instrRead(builder.regs.pc)

proc readAccum*(builder; num: uint32): IrInstrRef =
    assert num < 2
    builder.loadctx(ctxLoad64, uint32(offsetof(DspState, mainAccum)) + num * 8)

proc readAuxAccum*(builder; num: uint32): IrInstrRef =
    assert num < 2
    builder.loadctx(ctxLoadS32, uint32(offsetof(DspState, auxAccum)) + num * 4)

proc readProd*(builder): IrInstrRef =
    builder.loadctx(ctxLoad64, uint32(offsetof(DspState, prod)))

proc readProdCarry*(builder): IrInstrRef =
    builder.loadctx(ctxLoad16, uint32(offsetof(DspState, prodCarry)))

proc writeProdCarry*(builder; val: IrInstrRef) =
    builder.storectx(ctxStore16, uint32(offsetof(DspState, prodCarry)), val)

proc readFoldedProd*(builder): IrInstrRef =
    builder.signExt40(builder.biop(iAddX,
        builder.readProd(),
        builder.biop(lsl, builder.readProdCarry(), builder.imm(16))))

proc writeAccum*(builder; num: uint32, val: IrInstrRef) =
    assert num < 2
    builder.storectx(ctxStore64, uint32(offsetof(DspState, mainAccum)) + num * 8, val)

proc writeAuxAccum*(builder; num: uint32, val: IrInstrRef) =
    assert num < 2
    builder.storectx(ctxStore32, uint32(offsetof(DspState, auxAccum)) + num * 4, val)

proc writeProd*(builder; val: IrInstrRef) =
    builder.storectx(ctxStore64, uint32(offsetof(DspState, prod)), val)

proc writeFoldedProd*(builder; val: IrInstrRef) =
    builder.storectx(ctxStore64, uint32(offsetof(DspState, prod)), val)
    builder.storectx(ctxStore16, uint32(offsetof(DspState, prodcarry)), builder.imm(0))

proc readStatus*(builder): IrInstrRef =
    builder.loadctx(ctxLoad16, uint32(offsetof(DspState, status)))

proc readStatus*(builder; bit: DspStatusBit): IrInstrRef =
    builder.extractBit(builder.readStatus(), uint32(bit))

proc writeStatus*(builder; val: IrInstrRef) =
    builder.storectx(ctxStore16, uint32(offsetof(DspState, status)), val)

proc writeStatus*(builder; bit: DspStatusBit, val: IrInstrRef) =
    builder.writeStatus(builder.mergeBit(builder.readStatus(), val, uint32(bit)))

proc readAdr*(builder; num: uint32): IrInstrRef =
    assert num < 4
    builder.loadctx(ctxLoad16, uint32(offsetof(DspState, adrReg)) + num*2)

proc writeAdr*(builder; num: uint32, val: IrInstrRef) =
    assert num < 4
    builder.storectx(ctxStore16, uint32(offsetof(DspState, adrReg)) + num*2, val)

proc readAdrMod*(builder; num: uint32): IrInstrRef =
    assert num < 4
    builder.loadctx(ctxLoad16, uint32(offsetof(DspState, incReg)) + num*2)

proc writeAdrMod*(builder; num: uint32, val: IrInstrRef) =
    assert num < 4
    builder.storectx(ctxStore16, uint32(offsetof(DspState, incReg)) + num*2, val)

proc writeAdrLen*(builder; num: uint32, val: IrInstrRef) =
    assert num < 4
    builder.storectx(ctxStore16, uint32(offsetof(DspState, wrapReg)) + num*2, val)

proc readAdrLen*(builder; num: uint32): IrInstrRef =
    assert num < 4
    builder.loadctx(ctxLoad16, uint32(offsetof(DspState, wrapReg)) + num*2)

proc readDpp*(builder): IrInstrRef =
    builder.loadctx(ctxLoad16, uint32(offsetof(DspState, dpp)))

proc writeDpp*(builder; val: IrInstrRef) =
    builder.storectx(ctxStore16, uint32(offsetof(DspState, dpp)), val)

proc readReg*(builder; reg: DspReg): IrInstrRef =
    case reg
    of r0..r3:
        builder.readAdr(reg.uint32 - r0.uint32)
    of m0..m3:
        builder.readAdrMod(reg.uint32 - m0.uint32)
    of l0..l3:
        builder.readAdrLen(reg.uint32 - l0.uint32)
    of psr:
        builder.readStatus()
    of dpp:
        builder.readDpp()
    of DspReg.pcs..DspReg.lcs:
        builder.loadSpr(Spr.pcs.succ(reg.int - DspReg.pcs.int))
    of a0..b0:
        builder.unop(extractLo, builder.readAccum(reg.uint32 - a0.uint32))
    of a1..b1:
        builder.unop(extractMid, builder.readAccum(reg.uint32 - a1.uint32))
    of a2..b2:
        builder.unop(extractHi, builder.readAccum(reg.uint32 - a2.uint32))
    of x0..y0:
        builder.unop(extractLo, builder.readAuxAccum(reg.uint32 - x0.uint32))
    of x1..y1:
        builder.unop(extractMid, builder.readAuxAccum(reg.uint32 - x1.uint32))
    of ps0:
        builder.unop(extractLo, builder.readProd())
    of ps1:
        builder.unop(extractMid, builder.readProd())
    of ps2:
        builder.unop(extractHi, builder.readProd())
    of pc1:
        builder.readProdCarry()

proc writeReg*(builder; reg: DspReg, val: IrInstrRef) =
    case reg
    of r0..r3:
        builder.writeAdr(reg.uint32 - r0.uint32, val)
    of m0..m3:
        builder.writeAdrMod(reg.uint32 - m0.uint32, val)
    of l0..l3:
        builder.writeAdrLen(reg.uint32 - l0.uint32, val)
    of psr:
        builder.writeStatus(val)
    of dpp:
        builder.writeDpp(val)
    of DspReg.pcs..DspReg.lcs:
        builder.storeSpr(Spr.pcs.succ(reg.int - DspReg.pcs.int), val)
    of a0..b0:
        let accum = reg.uint32 - a0.uint32
        builder.writeAccum(accum, builder.biop(mergeLo, builder.readAccum(accum), val))
    of a1..b1:
        let accum = reg.uint32 - a1.uint32
        builder.writeAccum(accum, builder.biop(mergeMid, builder.readAccum(accum), val))
    of a2..b2:
        let accum = reg.uint32 - a2.uint32
        builder.writeAccum(accum, builder.biop(mergeHi, builder.readAccum(accum), val))
    of x0..y0:
        let accum = reg.uint32 - x0.uint32
        builder.writeAuxAccum(accum, builder.biop(mergeLo, builder.readAuxAccum(accum), val))
    of x1..y1:
        let accum = reg.uint32 - x1.uint32
        builder.writeAuxAccum(accum, builder.biop(mergeMidHi, builder.readAuxAccum(accum), val))
    of ps0:
        builder.writeProd(builder.biop(mergeLo, builder.readProd(), val))
    of ps1:
        builder.writeProd(builder.biop(mergeMid, builder.readProd(), val))
    of ps2:
        builder.writeProd(builder.biop(mergeHi, builder.readProd(), val))
    of pc1:
        builder.writeProdCarry(val)

proc incAdr*(builder; adr, wrap: IrInstrRef): IrInstrRef =
    let
        nextAdr = builder.biop(iAdd, adr, builder.imm(1))
        altAdr = builder.biop(iSub, adr, wrap)

        leftHand = builder.biop(bitXor, adr, nextAdr)
        rightHand = builder.biop(lsl, builder.biop(bitOr, wrap, builder.imm(1)), builder.imm(1))

    builder.biop(bitAnd,
        builder.triop(csel,
            altAdr, nextAdr, builder.biop(iCmpGreaterU, leftHand, rightHand)),
        builder.imm(0xFFFF))

proc decAdr*(builder; adr, wrap: IrInstrRef): IrInstrRef =
    let
        nextAdr = builder.biop(iAdd, adr, wrap)
        altAdr = builder.biop(iSub, adr, builder.imm(1))

        leftHand = builder.biop(bitXor, adr, nextAdr)
        rightHand = builder.biop(lsl, builder.biop(bitOr, wrap, builder.imm(1)), builder.imm(1))

    builder.biop(bitAnd,
        builder.triop(csel,
            altAdr, nextAdr, builder.biop(iCmpGreaterU, builder.biop(bitOr, leftHand, rightHand), wrap)),
        builder.imm(0xFFFF))

proc incAdr*(builder; adr, wrap, inc: IrInstrRef): IrInstrRef =
    discard

proc decAdr*(builder; adr, wrap, inc: IrInstrRef): IrInstrRef =
    discard

proc loadAccum*(builder; num: uint32, val: IrInstrRef) =
    let
        xl = builder.readStatus(dspStatusBitXl)

        mergeVal = builder.biop(mergeMid, builder.readAccum(num), val)
        signExtendedVal = builder.biop(lslX, builder.unop(extsh, val), builder.imm(16))

    builder.writeAccum(num, builder.triop(cselX, signExtendedVal, mergeVal, xl))

proc writeAccumSignExtend*(builder; num: uint32, val: IrInstrRef) =
    builder.writeAccum(num, builder.biop(asrX, builder.biop(lslX, val, builder.imm(24)), builder.imm(24)))

proc setE1*(builder; val: IrInstrRef) =
    builder.writeStatus dspStatusBitExt, builder.biop(iCmpEqualX, val, builder.unop(extswX, val))

proc setU1*(builder; val: IrInstrRef) =
    builder.writeStatus dspStatusBitUnnorm, builder.biop(lsr,
        builder.unop(bitNot, builder.biop(bitXor, val, builder.biop(lsl, val, builder.imm(1)))),
        builder.imm(31))
