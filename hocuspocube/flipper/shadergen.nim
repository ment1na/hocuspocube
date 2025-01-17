import
    strformat, hashes,
    rasterinterfacecommon,
    xf, bp, bpcommon

type
    VertexShaderKey* = object
        enabledAttrs*: set[VertexAttrKind]
        normalsNBT*: bool

        numTexcoordGen*: uint32
        texcoordGen*: array[8, TexcoordGen]

        enableDualTex*: bool
        normaliseDualTex*: set[0..7]

        numColors*: uint32
        lightCtrls*: array[LightCtrlKind, LightCtrl]

    FragmentShaderKey* = object
        numTevStages*: uint32
        colorEnv*: array[16, TevColorEnv]
        alphaEnv*: array[16, TevAlphaEnv]
        ras1Tref*: array[8, Ras1Tref]
        ksel*: array[8, TevKSel]
        alphaCompLogic*: AlphaCompLogic
        alphaComp0*, alphaComp1*: CompareFunction
        zenv1*: TevZEnv1

proc `==`*(a, b: VertexShaderKey): bool =
    result = a.enabledAttrs == b.enabledAttrs and
        a.numTexcoordGen == b.numTexcoordGen and
        a.numColors == b.numColors and
        a.enableDualTex == b.enableDualTex

    if result:
        for i in 0..<a.numTexcoordGen:
            if a.texcoordGen[i] != b.texcoordGen[i]:
                return false

        if a.numColors >= 1 and 
            a.lightCtrls[lightCtrlColor0] != b.lightCtrls[lightCtrlColor0] or
            a.lightCtrls[lightCtrlAlpha0] != b.lightCtrls[lightCtrlAlpha0]:
            return false
        if a.numColors == 2 and 
            a.lightCtrls[lightCtrlColor1] != b.lightCtrls[lightCtrlColor1] or
            a.lightCtrls[lightCtrlAlpha1] != b.lightCtrls[lightCtrlAlpha1]:
            return false
        if a.enableDualTex and a.normaliseDualTex != b.normaliseDualTex:
            return false

proc hash*(key: VertexShaderKey): Hash =
    result = result !& hash(key.enabledAttrs)
    result = result !& hash(key.numTexcoordGen)
    for i in 0..<key.numTexcoordGen:
        result = result !& hash(key.texcoordGen[i])
    result = result !& hash(key.numColors)
    if key.numColors >= 1:
        result = result !&
            hash(key.lightCtrls[lightCtrlColor0]) !&
            hash(key.lightCtrls[lightCtrlAlpha0])
    if key.numColors == 2:
        result = result !&
            hash(key.lightCtrls[lightCtrlColor1]) !&
            hash(key.lightCtrls[lightCtrlAlpha1])
    result = result !& hash(key.enableDualTex)
    if key.enableDualTex:
        result = result !& hash(key.normaliseDualTex)
    result = !$result

proc `==`*(a, b: FragmentShaderKey): bool =
    result =
        a.numTevStages == b.numTevStages and
        a.alphaCompLogic == b.alphaCompLogic and
        a.alphaComp0 == b.alphaComp0 and
        b.alphaComp1 == b.alphaComp1

    if result:
        if a.zenv1.op != b.zenv1.op or
            (a.zenv1.op != zenvOpDisable and a.zenv1.typ != b.zenv1.typ):
            return false

        for i in 0..<a.numTevStages:
            if a.colorEnv[i] != b.colorEnv[i]:
                return false
            if a.alphaEnv[i] != b.alphaEnv[i]:
                return false
            if a.ras1Tref.getRas1Tref(i) != b.ras1Tref.getRas1Tref(i):
                return false
            if a.ksel.getTevKSel(i) != b.ksel.getTevKSel(i):
                return false

            for j in 0'u32..<2:
                if a.ksel[a.alphaEnv[i].tswap*2+j].swaprb != b.ksel[a.alphaEnv[i].tswap*2+j].swaprb:
                    return false
                if a.ksel[a.alphaEnv[i].tswap*2+j].swapga != b.ksel[a.alphaEnv[i].tswap*2+j].swapga:
                    return false
                if a.ksel[a.alphaEnv[i].rswap*2+j].swaprb != b.ksel[a.alphaEnv[i].rswap*2+j].swaprb:
                    return false
                if a.ksel[a.alphaEnv[i].rswap*2+j].swapga != b.ksel[a.alphaEnv[i].rswap*2+j].swapga:
                    return false

proc hash*(key: FragmentShaderKey): Hash =
    result = result !& hash(key.numTevStages)
    result = result !& hash(key.alphaCompLogic)
    result = result !& hash(key.alphaComp0)
    result = result !& hash(key.alphaComp1)
    result = result !& hash(key.zenv1.op)
    if key.zenv1.op != zenvOpDisable:
        result = result !& hash(key.zenv1.typ)
    for i in 0..<key.numTevStages:
        result = result !& hash(key.colorEnv[i])
        result = result !& hash(key.alphaEnv[i])
        result = result !& hash(key.ras1Tref.getRas1Tref(i))
        result = result !& hash(key.ksel.getTevKSel(i))
        for j in 0'u32..<2:
            result = result !& hash(key.ksel[key.alphaEnv[i].tswap*2+j].swaprb)
            result = result !& hash(key.ksel[key.alphaEnv[i].tswap*2+j].swapga)
            result = result !& hash(key.ksel[key.alphaEnv[i].rswap*2+j].swaprb)
            result = result !& hash(key.ksel[key.alphaEnv[i].rswap*2+j].swapga)
    result = !$result

template line(str: string) =
    result &= str
    result &= '\n'

const
    registerUniformSource = """layout (std140, binding = 0) uniform Registers {
mat4 Projection;
uint MatIndices0, MatIndices1;
uint DualTexMatIdx0, DualTexMatIdx1;
vec4 TexcoordScale[4];
vec4 TextureSizes[8];
ivec4 RegValues[2];
ivec4 Konstants[2];
uvec4 MatColor;
uint AlphaRefs;
uint ZEnvBias;
};"""

func mapPackedArray2(n: uint32): (uint32, string) =
    if (n mod 2) == 0:
        (n div 2, "xy")
    else:
        (n div 2, "zw")

proc genVertexShader*(key: VertexShaderKey): string =
    line "#version 430 core"

    block:
        line "layout (location = 0) in vec3 inPosition;"
        var location = 1
        if vtxAttrPosNrmMat in key.enabledAttrs:
            line &"layout (location = {location}) in uint inPnmatIdx;"
            location += 1
        for i in 0..<8:
            if vtxAttrTexMat0.succ(i) in key.enabledAttrs:
                line &"layout (location = {location}) in uint inTexMatIdx{i};"
                location += 1
        if vtxAttrNormal in key.enabledAttrs:
            line &"layout (location = {location}) in vec3 inNormal;"
            location += 1
            if key.normalsNBT:
                line &"layout (location = {location}) in vec3 inBinormal;"
                location += 1
                line &"layout (location = {location}) in vec3 inTangent;"
                location += 1
        for i in 0..<2:
            if vtxAttrColor0.succ(i) in key.enabledAttrs:
                line &"layout (location = {location}) in vec4 inColor{i};"
                location += 1
        for i in 0..<8:
            if vtxAttrTexCoord0.succ(i) in key.enabledAttrs:
                line &"layout (location = {location}) in vec2 inTexcoord{i};"
                location += 1

    line "layout (location = 0) out vec4 outColor0;"
    line "layout (location = 1) out vec4 outColor1;"
    for i in 0..<8:
        line &"layout (location = {i+2}) out vec3 outTexcoord{i};"

    line registerUniformSource

    line "layout (std140, binding = 1) uniform xfMemory {"
    line "vec4 PosTexMats[64];"
    line "vec4 NrmMats[32];" # stupid padding
    line "vec4 DualTexMats[64];"
    line "uvec4 LightColor[2];"
    line "vec4 LightPositionA1[8];"
    line "vec4 LightDirectionA0[8];"
    line "vec4 LightRemainingFactors[8];"
    line "};"

    line "void main() {"

    if vtxAttrPosNrmMat in key.enabledAttrs:
        line "uint pnmatIdx = inPnmatIdx;"
    else:
        line "uint pnmatIdx = bitfieldExtract(MatIndices0, 0, 6);"

    line "vec4 position4 = vec4(inPosition, 1.0);"
    line """vec3 transformedPos = vec3(dot(position4, PosTexMats[pnmatIdx]),
                                        dot(position4, PosTexMats[pnmatIdx + 1U]),
                                        dot(position4, PosTexMats[pnmatIdx + 2U]));"""

    line "gl_Position = Projection * vec4(transformedPos, 1.0);"
    # move into our clipping space
    line "gl_Position.z += gl_Position.w;"

    for i in 0..<2:
        let swizzle = if i == 0: 'x' else: 'y'
        line &"vec4 ambientReg{i} = unpackUnorm4x8(MatColor.{swizzle}).abgr;"
    for i in 0..<2:
        let swizzle = if i == 0: 'z' else: 'w'
        line &"vec4 materialReg{i} = unpackUnorm4x8(MatColor.{swizzle}).abgr;"

    if vtxAttrNormal in key.enabledAttrs:
        line """vec3 transformedNormal = normalize(vec3(dot(inNormal, NrmMats[pnmatIdx].xyz),
                                            dot(inNormal, NrmMats[pnmatIdx + 1U].xyz),
                                            dot(inNormal, NrmMats[pnmatIdx + 2U].xyz)));"""
    else:
        line """vec3 transformedNormal = vec3(0);"""

    line "vec4 finalColor0 = vec4(0), finalColor1 = vec4(0);"
    for i in 0..<key.numColors:
        line "{"

        let
            colorLightCtrl = key.lightCtrls[lightCtrlColor0.succ(int i)]
            alphaLightCtrl = key.lightCtrls[lightCtrlAlpha0.succ(int i)]

            ambientColor = case colorLightCtrl.ambSrc
                of matColorSrcPerVertex: &"inColor{i}.rgb"
                of matColorSrcRegister: &"ambientReg{i}.rgb"
            ambientAlpha = case alphaLightCtrl.ambSrc
                of matColorSrcPerVertex: &"inColor{i}.a"
                of matColorSrcRegister: &"ambientReg{i}.a"
            materialColor = case colorLightCtrl.matSrc
                of matColorSrcPerVertex: &"inColor{i}.rgb"
                of matColorSrcRegister: &"materialReg{i}.rgb"
            materialAlpha = case alphaLightCtrl.matSrc
                of matColorSrcPerVertex: &"inColor{i}.a"
                of matColorSrcRegister: &"materialReg{i}.a"

        if matColorSrcPerVertex in {colorLightCtrl.ambSrc, alphaLightCtrl.ambSrc,
            colorLightCtrl.matSrc, alphaLightCtrl.matSrc} and vtxAttrColor0.succ(int i) notin key.enabledAttrs:
            line &"vec4 inColor{i} = vec4(0);"

        if colorLightCtrl.enableLighting:
            line &"finalColor{i}.rgb = {ambientColor};"
        else:
            line &"finalColor{i}.rgb = {materialColor};"

        if alphaLightCtrl.enableLighting:
            line &"finalColor{i}.a = {ambientAlpha};"
        else:
            line &"finalColor{i}.a = {materialAlpha};"

        proc calculateAtten(result: var string, light: int, ctrl: LightCtrl) =
            line &"vec3 lightPos = LightPositionA1[{light}].xyz;"
            line &"vec3 lightDir = LightDirectionA0[{light}].xyz;"
            line "vec3 torwardsLight = lightPos - transformedPos;"
            line "float torwardsLightLen = length(torwardsLight);"
            line "torwardsLight /= torwardsLightLen;"

            if ctrl.attenEnable:
                case ctrl.attenSelect
                of attenSelectDiffSpotlight:
                    line "float aattn = dot(torwardsLight, lightDir);"
                    line "float d = torwardsLightLen;"
                of attenSelectSpecular:
                    line "float aattn = dot(transformedNormal, lightDir);"
                    line "float d = aattn;"

                line &"""float atten = max((LightDirectionA0[{light}].w + LightPositionA1[{light}].w * aattn + aattn * aattn * LightRemainingFactors[{light}].x) /
                                        (LightRemainingFactors[{light}].y + LightRemainingFactors[{light}].z * aattn + aattn * aattn * LightRemainingFactors[{light}].w), 0);"""
            else:
                line "float atten = 1.0;"

            let diff =
                    case ctrl.diffAtten
                    of diffuseAtten1: "1.0"
                    of diffuseAttenNL: "dot(transformedNormal, torwardsLight)"
                    of diffuseAttenNLClamped: "max(dot(transformedNormal, torwardsLight), 0)"
                    else: raiseAssert("diffuse attenuation reserved value!")
            line &"atten *= {diff};"

        for j in 0..<8:
            let
                enableColor = colorLightCtrl.enableLighting and colorLightCtrl.lights(j)
                enableAlpha = alphaLightCtrl.enableLighting and alphaLightCtrl.lights(j)
            if enableColor or enableAlpha:
                line "{"
                let
                    lightColorIdx = if j >= 4: 1 else: 0
                    lightColorSwizzle = case range[0..3](j mod 4)
                        of 0: 'x'
                        of 1: 'y'
                        of 2: 'z'
                        of 3: 'w'
                line &"vec4 lightColor = unpackUnorm4x8(LightColor[{lightColorIdx}].{lightColorSwizzle}).abgr;"
                if enableColor:
                    line "{"
                    calculateAtten(result, j, colorLightCtrl)
                    line &"finalColor{i}.rgb += atten * lightColor.rgb;"
                    line "}"
                if enableAlpha:
                    line "{"
                    calculateAtten(result, j, alphaLightCtrl)
                    line &"finalColor{i}.a += atten * lightColor.a;"
                    line "}"
                line "}"

        if colorLightCtrl.enableLighting:
            line &"finalColor{i}.rgb = clamp(finalColor{i}.rgb * {materialColor}, 0, 1);"
        if alphaLightCtrl.enableLighting:
            line &"finalColor{i}.a = clamp(finalColor{i}.a * {materialAlpha}, 0, 1);"

        line &"outColor{i} = finalColor{i} * 255.0;"

        line "}"

    for i in 0..<key.numTexcoordGen:
        line "{"

        case key.texcoordGen[i].kind
        of texcoordGenKindRegular:
            let src =
                case key.texcoordGen[i].src
                of texcoordGenSrcGeom: "vec4(inPosition, 1.0)"
                of texcoordGenSrcNrm: "vec4(inNormal, 1.0)"
                of texcoordGenSrcTex0..texcoordGenSrcTex7:
                    let n = ord(texcoordGen[i].src) - ord(texcoordGenSrcTex0)
                    if vtxAttrTexCoord0.succ(n) in key.enabledAttrs:
                        &"vec4(inTexcoord{n}, 1.0, 1.0)"
                    else:
                        "vec4(0.0, 0.0, 0.0, 1.0)" # what happens then?
                else: raiseAssert(&"texcoord source {key.texcoordGen[i].src} not implemented yet")

            line &"vec4 texcoordSrc = {src};"
            if vtxAttrTexMat0.succ(int i) in key.enabledAttrs:
                line &"uint matIdx = inTexMatIdx{i};"
            else:
                let
                    matVar = if i >= 4: 1 else: 0
                    matShift = if i >= 4: (i-4)*6 else: i*6+6
                line &"uint matIdx = bitfieldExtract(MatIndices{matVar}, {matShift}, 6);"

            # not pretty, but it works
            if key.texcoordGen[i].inputForm == texcoordInputFormAB11:
                line "texcoordSrc.z = 1.0;"

            case key.texcoordGen[i].proj
            of texcoordProjSt:
                line """vec3 transformedTexcoord = vec3(dot(texcoordSrc, PosTexMats[matIdx]),
                                            dot(texcoordSrc, PosTexMats[matIdx+1U]),
                                            1.0);"""
            of texcoordProjStq:
                line """vec3 transformedTexcoord = vec3(dot(texcoordSrc, PosTexMats[matIdx]),
                                                        dot(texcoordSrc, PosTexMats[matIdx+1U]),
                                                        dot(texcoordSrc, PosTexMats[matIdx+2U]));"""

            if key.enableDualTex:
                if i in key.normaliseDualTex:
                    line "transformedTexcoord = normalize(transformedTexcoord);"

                line &"uint postMatIdx = bitfieldExtract(DualTexMatIdx{i div 4}, {(i mod 4)*8}, 8);"
                line """transformedTexcoord = vec3(dot(vec4(transformedTexcoord, 1.0), DualTexMats[postMatIdx]),
                                        dot(vec4(transformedTexcoord, 1.0), DualTexMats[postMatIdx + 1U]),
                                        dot(vec4(transformedTexcoord, 1.0), DualTexMats[postMatIdx + 2U]));"""
        of texcoordGenKindColorStrgbc0, texcoordGenKindColorStrgbc1:
            let idx = ord(key.texcoordGen[i].kind)-ord(texcoordGenKindColorStrgbc0)
            line &"vec3 transformedTexcoord = vec3(finalColor{idx}.rg, 1.0);"
        of texcoordGenKindEmbossMap:
            raiseAssert("emboss texture coord gen not implemented")

        let (scaleIdx, scaleSwizzle) = mapPackedArray2(i)
        line &"outTexcoord{i} = transformedTexcoord * vec3(TexcoordScale[{scaleIdx}].{scaleSwizzle}, 1.0);"
        line "}"

    line "}"

proc signedExtract(val: string, start, bits: int): string =
    &"(({val} << {32 - bits - start}) >> {32 - bits})"

proc swizzleFromSwapTable(idx: uint32, swaptable: array[8, TevKSel]): string =
    const letters: array[4, char] = ['r', 'g', 'b', 'a']
    result &= letters[swaptable[idx*2+0].swaprb]
    result &= letters[swaptable[idx*2+0].swapga]
    result &= letters[swaptable[idx*2+1].swaprb]
    result &= letters[swaptable[idx*2+1].swapga]

proc genFragmentShader*(key: FragmentShaderKey): string =
    line "#version 430 core"

    line "layout (location = 0) in vec4 inColor0;"
    line "layout (location = 1) in vec4 inColor1;"
    for i in 0..<8:
        line &"layout (location = {2+i}) in vec3 inTexcoord{i};"

    line "layout (binding = 0) uniform sampler2D Textures[8];"

    line "out vec4 outColor;"

    line registerUniformSource

    line "void main() {"

    for i in 0..<4:
        let
            swizzle0 = if (i mod 2) == 0: "x" else: "z"
            swizzle1 = if (i mod 2) == 0: "y" else: "w"
            idx = i div 2
            konstR = signedExtract(&"Konstants[{idx}].{swizzle0}", 0, 11)
            konstG = signedExtract(&"Konstants[{idx}].{swizzle1}", 12, 11)
            konstB = signedExtract(&"Konstants[{idx}].{swizzle1}", 0, 11)
            konstA = signedExtract(&"Konstants[{idx}].{swizzle0}", 12, 11)
            regR = signedExtract(&"RegValues[{idx}].{swizzle0}", 0, 11)
            regG = signedExtract(&"RegValues[{idx}].{swizzle1}", 12, 11)
            regB = signedExtract(&"RegValues[{idx}].{swizzle1}", 0, 11)
            regA = signedExtract(&"RegValues[{idx}].{swizzle0}", 12, 11)
        line &"ivec4 reg{i} = ivec4({regR}, {regG}, {regB}, {regA});"
        line &"ivec4 konst{i} = ivec4({konstR}, {konstG}, {konstB}, {konstA});"

    if key.zenv1.op != zenvOpDisable:
        line "ivec4 lastTexColor;"

    for i in 0..<key.numTevStages:
        line "{"
        const
            mapColorOperand: array[TevColorEnvSel, string] =
                ["reg0.rgb", "reg0.aaa", "reg1.rgb", "reg1.aaa", "reg2.rgb", "reg2.aaa", "reg3.rgb", "reg3.aaa",
                    "texcolor.rgb", "texcolor.aaa", "rascolor.rgb", "rascolor.aaa",
                    "ivec3(255)", "ivec3(128)", "konstant.rgb", "ivec3(0)"]
            mapAlphaOperand: array[TevAlphaEnvSel, string] =
                ["reg0.a", "reg1.a", "reg2.a", "reg3.a", "texcolor.a", "rascolor.a", "konstant.a", "0"]

            mapColorKonstant: array[TevKColorSel, string] =
                ["ivec3(255)", "ivec3(255*7/8)", "ivec3(255*3/4)", "ivec3(255*5/8)", "ivec3(255*1/2)", "ivec3(255*3/8)",
                    "ivec3(255*1/4)", "ivec3(255*1/8)",
                    "0", "0", "0", "0",
                    "konst0.rgb", "konst1.rgb", "konst2.rgb", "konst3.rgb",
                    "konst0.rrr", "konst1.rrr", "konst2.rrr", "konst3.rrr",
                    "konst0.ggg", "konst1.ggg", "konst2.ggg", "konst3.ggg",
                    "konst0.bbb", "konst1.bbb", "konst2.bbb", "konst3.bbb",
                    "konst0.aaa", "konst1.aaa", "konst2.aaa", "konst3.aaa"]
            mapAlphaKonstant: array[TevKAlphaSel, string] =
                ["255", "(255*7/8)", "(255*3/4)", "(255*5/8)", "(255*1/2)", "(255*3/8)",
                    "(255*1/4)", "(255*1/8)",
                    "0", "0", "0", "0", "0", "0", "0", "0",
                    "konst0.r", "konst1.r", "konst2.r", "konst3.r",
                    "konst0.g", "konst1.g", "konst2.g", "konst3.g",
                    "konst0.b", "konst1.b", "konst2.b", "konst3.b",
                    "konst0.a", "konst1.a", "konst2.a", "konst3.a"]

        let
            colorEnv = key.colorEnv[i]
            alphaEnv = key.alphaEnv[i]

            (texmap, texcoordNum, texmapEnable, color) = key.ras1tref.getRas1Tref(i)
            (kselColor, kselAlpha) = key.ksel.getTevKSel(i)

            colorDst = &"reg{colorEnv.dst}.rgb"
            alphaDst = &"reg{alphaEnv.dst}.a"

            colorOp = if colorEnv.sub: "-" else: "+"
            alphaOp = if alphaEnv.sub: "-" else: "+"

            colorA = mapColorOperand[colorEnv.sela]
            colorB = mapColorOperand[colorEnv.selb]
            colorC = mapColorOperand[colorEnv.selc]
            colorD = mapColorOperand[colorEnv.seld]
            alphaA = mapAlphaOperand[alphaEnv.sela]
            alphaB = mapAlphaOperand[alphaEnv.selb]
            alphaC = mapAlphaOperand[alphaEnv.selc]
            alphaD = mapAlphaOperand[alphaEnv.seld]

            colorKonstant = mapColorKonstant[kselColor]
            alphaKonstant = mapAlphaKonstant[kselAlpha]

            rascolor = case color
                of ras1trefColorColor0: "inColor0"
                of ras1trefColorColor1: "inColor1"
                of ras1trefColorZero: "vec4(0)"
                else: "unimplemented"

        let colorSwizzle = swizzleFromSwapTable(alphaEnv.rswap, key.ksel)
        line &"ivec4 rascolor = ivec4({rascolor}).{colorSwizzle};"

        line &"ivec4 konstant = ivec4({colorKonstant}, {alphaKonstant});"

        if texmapEnable:
            let textureSwizzle = swizzleFromSwapTable(alphaEnv.tswap, key.ksel)
            line &"ivec4 texcolor = ivec4(texture(Textures[{texmap}], round(inTexcoord{texcoordNum}.xy) * TextureSizes[{texmap}].zw) * 255.0).{textureSwizzle};"
        else:
            # welp what happens here?
            line &"ivec4 texcolor = ivec4(0xFFU);"

        if key.zenv1.op != zenvOpDisable:
            # does swizzle affect z textures?
            line "lastTexColor = texcolor;"

        line &"uvec3 colorA8 = uvec3({colorA}) & 0xFFU;"
        line &"uvec3 colorB8 = uvec3({colorB}) & 0xFFU;"
        line &"uvec3 colorC8 = uvec3({colorC}) & 0xFFU;"

        line &"uint alphaA8 = uint({alphaA}) & 0xFFU;"
        line &"uint alphaB8 = uint({alphaB}) & 0xFFU;"
        line &"uint alphaC8 = uint({alphaC}) & 0xFFU;"

        const
            compOpOperandsLeft: array[TevCompOperand, string] = [
                "colorA8.r",
                "bitfieldInsert(colorA8.r, colorA8.g, 8, 8)",
                "bitfieldInsert(colorA8.r, bitfieldInsert(colorA8.g, colorA8.b, 8, 8), 8, 16)",
                "alphaA8"]
            compOpOperandsRight: array[TevCompOperand, string] = [
                "colorB8.r",
                "bitfieldInsert(colorB8.r, colorB8.g, 8, 8)",
                "bitfieldInsert(colorB8.r, bitfieldInsert(colorB8.g, colorB8.b, 8, 8), 8, 16)",
                "alphaB8"]
            compOpOperator: array[bool, string] = ["==", ">"]

        if colorEnv.bias == tevBiasCompareOp:
            line &"ivec3 colorVal = {colorD};"
            if colorEnv.compOp == tevCompOperandRGB8:
                let compOp = if colorEnv.equal: "equal" else: "greaterThan"
                line &"colorVal = mix(colorVal, colorVal + ivec3(colorC8), {compOp}(colorA8, colorB8));"
            else:
                line &"if ({compOpOperandsLeft[colorEnv.compOp]} {compOpOperator[colorEnv.equal]} {compOpOperandsRight[colorEnv.compOp]})"
                line "colorVal += ivec3(colorC8);"
        else:
            line &"ivec3 colorVal = ({colorD} << 8) {colorOp} ivec3((255 - colorC8) * colorA8 + colorC8 * colorB8);"

            case colorEnv.bias
            of tevBiasZero: discard
            of tevBiasHalf: line "colorVal += 0x8000;"
            of tevBiasMinusHalf: line "colorVal -= 0x8000;"
            of tevBiasCompareOp: discard

            case colorEnv.scale
            of tevScale1: discard
            of tevScale2: line "colorVal <<= 1;"
            of tevScale4: line "colorVal <<= 2;"
            of tevScaleHalf: line "colorVal >>= 1;"

            line "colorVal >>= 8;"

        if colorEnv.clamp:
            line &"{colorDst} = clamp(colorVal, 0, 255);"
        else:
            line &"{colorDst} = clamp(colorVal, -1024, 1023);"

        if alphaEnv.bias == tevBiasCompareOp:
            line &"int alphaVal = {alphaD};"
            line &"if ({compOpOperandsLeft[alphaEnv.compOp]} {compOpOperator[alphaEnv.equal]} {compOpOperandsRight[alphaEnv.compOp]})"
            line "alphaVal += int(alphaC8);"
        else:
            line &"int alphaVal = ({alphaD} << 8) {alphaOp} int((255 - alphaC8) * alphaA8 + alphaC8 * alphaB8);"

            case alphaEnv.bias
            of tevBiasZero: discard
            of tevBiasHalf: line "alphaVal += 0x8000;"
            of tevBiasMinusHalf: line "alphaVal -= 0x8000;"
            of tevBiasCompareOp: discard

            case alphaEnv.scale
            of tevScale1: discard
            of tevScale2: line "alphaVal <<= 1;"
            of tevScale4: line "alphaVal <<= 2;"
            of tevScaleHalf: line "alphaVal >>= 1;"

            line "alphaVal >>= 8;"

        if alphaEnv.clamp:
            line &"{alphaDst} = clamp(alphaVal, 0, 255);"
        else:
            line &"{alphaDst} = clamp(alphaVal, -1024, 1023);"

        line "}"

    # these are only the most common cases where the result is constant
    # always discard is probably pretty rare, so we don't handle this
    # we leave the remaining cases to the shader optimiser
    # this is mostly to reduce bloat
    let skipAlphaTest = (case key.alphaCompLogic
        of alphaCompLogicAnd: key.alphaComp0 == compareAlways and key.alphaComp1 == compareAlways
        of alphaCompLogicOr: key.alphaComp0 == compareAlways or key.alphaComp1 == compareAlways
        else: false)

    if not skipAlphaTest:
        line "{"

        const
            translateComp: array[CompareFunction, string] =
                ["false", "reg0.a < ref", "reg0.a == ref", "reg0.a <= ref",
                "reg0.a > ref", "reg0.a != ref", "reg0.a >= ref", "true"]
            translateLogicOp: array[AlphaCompLogic, string] = ["&&", "||", "!=", "=="]

        let
            comp0 = translateComp[key.alphaComp0]
            comp1 = translateComp[key.alphaComp1]
            logic = translateLogicOp[key.alphaCompLogic]

        line "uint ref = bitfieldExtract(AlphaRefs, 0, 8);"
        line &"bool test1 = {comp0};"
        line "ref = bitfieldExtract(AlphaRefs, 8, 8);"
        line &"bool test2 = {comp1};"

        line &"if (!(test1 {logic} test2))"
        line "discard;"

        line "}"

    if key.zenv1.op != zenvOpDisable:
        line "{"

        const translateVal: array[ZEnvOpType, string] =
            ["lastTexColor.a", "(lastTexColor.a << 8) | lastTexColor.r",
                "(lastTexColor.r << 16) | (lastTexColor.g << 8) | lastTexColor.r", "0"]

        let val = translateVal[key.zenv1.typ]
        line &"float depth = float({val} + ZEnvBias) / 16777216.0;"

        if key.zenv1.op == zenvOpAdd:
            line "gl_FragDepth = gl_FragCoord.z + depth;"
        else:
            line "gl_FragDepth = depth;"

        line "}"

    line "outColor = vec4(reg0) / 255.0;"
    line "}"
