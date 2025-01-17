import
    ../../util/aluhelper,
    ../../util/jit/ir, ppcfrontendcommon,
    fallbacks,
    ../ppcstate

using builder: var IrBlockBuilder[PpcIrRegState]

proc calcAdrImm(builder; a, imm: uint32, update: bool): IrInstrRef =
    if not update and a == 0:
        builder.imm(signExtend(imm, 16))
    else:
        builder.biop(iAdd, builder.loadreg(a), builder.imm(signExtend(imm, 16)))

proc calcAdrImmQuant(builder; a, imm: uint32, update: bool): IrInstrRef =
    if not update and a == 0:
        builder.imm(signExtend(imm, 12))
    else:
        builder.biop(iAdd, builder.loadreg(a), builder.imm(signExtend(imm, 12)))

proc calcAdr(builder; a, b: uint32, update: bool): IrInstrRef =
    result = (if not update and a == 0:
                builder.loadreg(b)
            else:
                builder.biop(iAdd, builder.loadreg(a), builder.loadreg(b)))

proc intload(builder; loadKind: InstrKind, d, a, b: uint32, update: bool, algebraic = false) =
    let
        adr = builder.calcAdr(a, b, update)
        val = builder.unop(loadKind, adr)
    builder.storereg d, (if algebraic: builder.unop(extsh, val) else: val)
    if update:
        builder.storereg a, adr

proc intloadImm(builder; loadKind: InstrKind, d, a, imm: uint32, update: bool, algebraic = false) =
    let
        adr = builder.calcAdrImm(a, imm, update)
        val = builder.unop(loadKind, adr)
    builder.storereg d, (if algebraic: builder.unop(extsh, val) else: val)
    if update:
        builder.storereg a, adr

proc intstore(builder; storekind: InstrKind, s, a, b: uint32, update: bool) =
    let adr = builder.calcAdr(a, b, update)
    discard builder.biop(storekind, adr, builder.loadreg(s))
    if update:
        builder.storereg a, adr

proc intstoreimm(builder; storekind: InstrKind, s, a, imm: uint32, update: bool) =
    let adr = builder.calcAdrImm(a, imm, update)
    discard builder.biop(storekind, adr, builder.loadreg(s))
    if update:
        builder.storereg a, adr

const
    interpretLoadStore = false
    interpretRegularFloatMem = false
    interpretQuantLoadStore = true

    interpretLoads = false
    interpretStores = false

    interpretLoads8 = false
    interpretLoadsS16 = false
    interpretLoadsU16 = false

    interpretLoadStoreUpdate = false

proc lbz*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoads8:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lbz)
    else:
        builder.intloadImm(ppcLoadU8, d, a, imm, false)

proc lbzu*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoads8 or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lbzu)
    else:
        builder.intloadImm(ppcLoadU8, d, a, imm, true)

proc lbzux*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoads8 or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lbzux)
    else:
        builder.intload(ppcLoadU8, d, a, b, true)

proc lbzx*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoads8:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lbzx)
    else:
        builder.intload(ppcLoadU8, d, a, b, false)

proc lha*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsS16:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lha)
    else:
        builder.intloadImm(ppcLoadU16, d, a, imm, false, true)

proc lhau*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsS16 or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lhau)
    else:
        builder.intloadImm(ppcLoadU16, d, a, imm, true, true)

proc lhaux*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsS16 or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lhaux)
    else:
        builder.intload(ppcLoadU16, d, a, b, true, true)

proc lhax*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsS16:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lhax)
    else:
        builder.intload(ppcLoadU16, d, a, b, false, true)

proc lhz*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsU16:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lhz)
    else:
        builder.intloadImm(ppcLoadU16, d, a, imm, false)

proc lhzu*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsU16 or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lhzu)
    else:
        builder.intloadImm(ppcLoadU16, d, a, imm, true)

proc lhzux*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsU16 or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lhzux)
    else:
        builder.intload(ppcLoadU16, d, a, b, true)

proc lhzx*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadsU16:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lhzx)
    else:
        builder.intload(ppcLoadU16, d, a, b, false)

proc lwz*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lwz)
    else:
        builder.intloadImm(ppcLoad32, d, a, imm, false)

proc lwzu*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lwzu)
    else:
        builder.intloadImm(ppcLoad32, d, a, imm, true)

proc lwzux*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lwzux)
    else:
        builder.intload(ppcLoad32, d, a, b, true)

proc lwzx*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretLoads:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lwzx)
    else:
        builder.intload(ppcLoad32, d, a, b, false)

proc stb*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretStores:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stb)
    else:
        builder.intstoreimm(ppcStore8, s, a, imm, false)

proc stbu*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretStores or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stbu)
    else:
        builder.intstoreimm(ppcStore8, s, a, imm, true)

proc stbux*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretStores or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stbux)
    else:
        builder.intstore(ppcStore8, s, a, b, true)

proc stbx*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretStores:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stbx)
    else:
        builder.intstore(ppcStore8, s, a, b, false)

proc sth*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretStores:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.sth)
    else:
        builder.intstoreimm(ppcStore16, s, a, imm, false)

proc sthu*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretStores or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.sthu)
    else:
        builder.intstoreimm(ppcStore16, s, a, imm, true)

proc sthux*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretStores or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.sthux)
    else:
        builder.intstore(ppcStore16, s, a, b, true)

proc sthx*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretStores:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.sthx)
    else:
        builder.intstore(ppcStore16, s, a, b, false)

proc stw*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretStores:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stw)
    else:
        builder.intstoreimm(ppcStore32, s, a, imm, false)

proc stwu*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretStores or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stwu)
    else:
        builder.intstoreimm(ppcStore32, s, a, imm, true)

proc stwux*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretStores or interpretLoadStoreUpdate:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stwux)
    else:
        builder.intstore(ppcStore32, s, a, b, true)

proc stwx*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretStores:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stwx)
    else:
        builder.intstore(ppcStore32, s, a, b, false)

proc lhbrx*(builder; d, a, b: uint32) =
    raiseAssert("unimplemented instr lhbrx")

proc lwbrx*(builder; d, a, b: uint32) =
    raiseAssert("unimplemented instr lwbrx")

proc sthbrx*(builder; s, a, b: uint32) =
    raiseAssert("unimplemented instr sthbrx")

proc stwbrx*(builder; s, a, b: uint32) =
    raiseAssert("unimplemented instr stwbrx")

template calcAddrMultiple(start: uint32, body: untyped): untyped {.dirty.} =
    var
        ea = builder.calcAdrImm(a, imm, false)
        r = start
    while r <= 31:
        body

        r += 1
        ea = builder.biop(iAdd, ea, builder.imm(4))

proc lmw*(builder; d, a, imm: uint32) =
    when interpretLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lmw)
    else:
        calcAddrMultiple d:
            builder.storereg r, builder.unop(ppcLoad32, ea)

proc stmw*(builder; s, a, imm: uint32) =
    when interpretLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stmw)
    else:
        calcAddrMultiple s:
            discard builder.biop(ppcStore32, ea, builder.loadreg(r))

proc lswi*(builder; d, a, nb: uint32) =
    raiseAssert("unimplemented instr lswi")

proc lswx*(builder; d, a, b: uint32) =
    raiseAssert("unimplemented instr lswx")

proc stswi*(builder; s, a, nb: uint32) =
    raiseAssert "instr not implemented stswi"

proc stswx*(builder; s, a, b: uint32) =
    raiseAssert "instr not implemented stswx"

# Float

proc expand(builder; instr: IrInstrRef): IrInstrRef =
    builder.unop(cvtss2sd, instr)

proc lfd*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfd)
    else:
        let adr = builder.calcAdrImm(a, imm, false)
        builder.storefregLowOnly d, builder.unop(ppcLoadFsd, adr)
    builder.regs.floatInstr = true

proc lfdu*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfdu)
    else:
        let adr = builder.calcAdrImm(a, imm, true)
        builder.storereg a, adr
        builder.storefregLowOnly d, builder.unop(ppcLoadFsd, adr)
    builder.regs.floatInstr = true

proc lfdux*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfdux)
    else:
        let adr = builder.calcAdr(a, b, true)
        builder.storereg a, adr
        builder.storefregLowOnly d, builder.unop(ppcLoadFsd, adr)
    builder.regs.floatInstr = true

proc lfdx*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfdx)
    else:
        let adr = builder.calcAdr(a, b, false)
        builder.storefregLowOnly d, builder.unop(ppcLoadFsd, adr)
    builder.regs.floatInstr = true

proc lfs*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfs)
    else:
        let adr = builder.calcAdrImm(a, imm, false)
        builder.storefregReplicate d, builder.expand(builder.unop(ppcLoadFss, adr))
    builder.regs.floatInstr = true

proc lfsu*(builder; d, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfsu)
    else:
        let adr = builder.calcAdrImm(a, imm, true)
        builder.storereg a, adr
        builder.storefregReplicate d, builder.expand(builder.unop(ppcLoadFss, adr))
    builder.regs.floatInstr = true

proc lfsux*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfsux)
    else:
        let adr = builder.calcAdr(a, b, true)
        builder.storereg a, adr
        builder.storefregReplicate d, builder.expand(builder.unop(ppcLoadFss, adr))
    builder.regs.floatInstr = true

proc lfsx*(builder; d, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.lfsx)
    else:
        let adr = builder.calcAdr(a, b, false)
        builder.storefregReplicate d, builder.expand(builder.unop(ppcLoadFss, adr))
    builder.regs.floatInstr = true

proc stfd*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfd)
    else:
        let adr = builder.calcAdrImm(a, imm, false)
        discard builder.biop(ppcStoreFsd, adr, builder.loadfreg(s))
    builder.regs.floatInstr = true

proc stfdu*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfdu)
    else:
        let adr = builder.calcAdrImm(a, imm, true)
        builder.storereg a, adr
        discard builder.biop(ppcStoreFsd, adr, builder.loadfreg(s))
    builder.regs.floatInstr = true

proc stfdux*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfdux)
    else:
        let adr = builder.calcAdr(a, b, true)
        builder.storereg a, adr
        discard builder.biop(ppcStoreFsd, adr, builder.loadfreg(s))
    builder.regs.floatInstr = true

proc stfdx*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfdx)
    else:
        let adr = builder.calcAdr(a, b, false)
        discard builder.biop(ppcStoreFsd, adr, builder.loadfreg(s))
    builder.regs.floatInstr = true

proc stfiwx*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfiwx)
    else:
        let adr = builder.calcAdr(a, b, false)
        discard builder.biop(ppcStoreFss, adr, builder.loadfreg(s))
    builder.regs.floatInstr = true

proc stfs*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfs)
    else:
        discard builder.biop(ppcStoreFss, builder.calcAdrImm(a, imm, false), builder.unop(cvtsd2ss, builder.loadfreg(s)))
    builder.regs.floatInstr = true

proc stfsu*(builder; s, a, imm: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfsu)
    else:
        let adr = builder.calcAdrImm(a, imm, true)
        builder.storereg a, adr
        discard builder.biop(ppcStoreFss, adr, builder.unop(cvtsd2ss, builder.loadfreg(s)))
    builder.regs.floatInstr = true

proc stfsux*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfsux)
    else:
        let adr = builder.calcAdr(a, b, true)
        builder.storereg a, adr
        discard builder.biop(ppcStoreFss, adr, builder.unop(cvtsd2ss, builder.loadfreg(s)))
    builder.regs.floatInstr = true

proc stfsx*(builder; s, a, b: uint32) =
    when interpretLoadStore or interpretRegularFloatMem:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.stfsx)
    else:
        let adr = builder.calcAdr(a, b, false)
        discard builder.biop(ppcStoreFss, adr, builder.unop(cvtsd2ss, builder.loadfreg(s)))
    builder.regs.floatInstr = true

proc quantload(builder; adr: IrInstrRef, d, w, i: uint32) =
    builder.storefregp d, builder.unop(cvtps2pd,
        builder.biop(if w == 1: ppcLoadFsq else: ppcLoadFpq,
            adr,
            builder.loadctx(ctxLoadU32, uint32(offsetof(PpcState, gqr)) + i*4)))

proc quantstore(builder; adr: IrInstrRef, s, w, i: uint32) =
    let
        storeval =
            if w == 1:
                builder.unop(cvtsd2ss, builder.loadfreg(s))
            else:
                builder.unop(cvtpd2ps, builder.loadfreg(s))

    discard builder.triop(if w == 1: ppcStoreFsq else: ppcStoreFpq,
        adr,
        storeval,
        builder.loadctx(ctxLoadU32, uint32(offsetof(PpcState, gqr)) + i*4))

proc psq_lx*(builder; d, a, b, w, i: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_lx)
    else:
        builder.quantload builder.calcAdr(a, b, false), d, w, i
    builder.regs.floatInstr = true

proc psq_stx*(builder; s, a, b, w, i: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_stx)
    else:
        builder.quantstore builder.calcAdr(a, b, false), s, w, i
    builder.regs.floatInstr = true

proc psq_lux*(builder; d, a, b, w, i: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_lux)
    else:
        builder.quantload builder.calcAdr(a, b, true), d, w, i
    builder.regs.floatInstr = true

proc psq_stux*(builder; s, a, b, w, i: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_stux)
    else:
        builder.quantstore builder.calcAdr(a, b, true), s, w, i
    builder.regs.floatInstr = true

proc psq_l*(builder; d, a, w, i, imm: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_l)
    else:
        builder.quantload builder.calcAdrImmQuant(a, imm, false), d, w, i
    builder.regs.floatInstr = true

proc psq_lu*(builder; d, a, w, i, imm: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_lu)
    else:
        builder.quantload builder.calcAdrImmQuant(a, imm, true), d, w, i
    builder.regs.floatInstr = true

proc psq_st*(builder; s, a, w, i, imm: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_st)
    else:
        builder.quantstore builder.calcAdrImmQuant(a, imm, false), s, w, i
    builder.regs.floatInstr = true

proc psq_stu*(builder; s, a, w, i, imm: uint32) =
    when interpretLoadStore or interpretQuantLoadStore:
        builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.psq_stu)
    else:
        builder.quantstore builder.calcAdrImmQuant(a, imm, true), s, w, i
    builder.regs.floatInstr = true

# not really a load/store operation
proc dcbz*(builder; a, b: uint32) =
    builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.dcbz)

proc dcbz_l*(builder; a, b: uint32) =
    builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.dcbz_l)

proc icbi*(builder; a, b: uint32) =
    builder.interpretppc(builder.regs.instr, builder.regs.pc, fallbacks.icbi)
