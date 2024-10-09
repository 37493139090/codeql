package com.github.codeql

import org.jetbrains.kotlin.analysis.api.symbols.KaClassSymbol
import org.jetbrains.kotlin.analysis.api.types.KaClassType
import org.jetbrains.kotlin.analysis.api.types.KaType

private fun KotlinUsesExtractor.useClassType(
    c: KaClassType
): TypeResults {
    // TODO: this cast is unsafe; .symbol is actually a KaClassLikeSymbol
    val javaResult = TypeResult(addClassLabel(c.symbol as KaClassSymbol) /* , TODO, TODO */)
    val kotlinResult = TypeResult(fakeKotlinType() /* , "TODO", "TODO" */)
    return TypeResults(javaResult, kotlinResult)
}

fun KotlinUsesExtractor.useType(t: KaType?, context: TypeContext = TypeContext.OTHER): TypeResults {
    when (t) {
        null -> {
            logger.error("Unexpected null type")
            return extractErrorType()
        }
        is KaClassType -> return useClassType(t)
        else -> TODO()
    }
    /*
    OLD: KE1
            when (t) {
                is IrSimpleType -> return useSimpleType(t, context)
                else -> {
                    logger.error("Unrecognised IrType: " + t.javaClass)
                    return extractErrorType()
                }
            }
    */
}

private fun KotlinUsesExtractor.extractJavaErrorType(): TypeResult<DbErrortype> {
    val typeId = tw.getLabelFor<DbErrortype>("@\"errorType\"") { tw.writeError_type(it) }
    return TypeResult(typeId /* TODO , "<CodeQL error type>", "<CodeQL error type>" */)
}

private fun KotlinUsesExtractor.extractErrorType(): TypeResults {
    val javaResult = extractJavaErrorType()
    val kotlinTypeId =
        tw.getLabelFor<DbKt_nullable_type>("@\"errorKotlinType\"") {
            tw.writeKt_nullable_types(it, javaResult.id)
        }
    return TypeResults(
        javaResult,
        TypeResult(kotlinTypeId /* TODO , "<CodeQL error type>", "<CodeQL error type>" */)
    )
}

// TODO
fun KotlinUsesExtractor.fakeKotlinType(): Label<out DbKt_type> {
    val fakeKotlinPackageId: Label<DbPackage> =
        tw.getLabelFor("@\"FakeKotlinPackage\"", { tw.writePackages(it, "fake.kotlin") })
    val fakeKotlinClassId: Label<DbClassorinterface> =
        tw.getLabelFor(
            "@\"FakeKotlinClass\"",
            { tw.writeClasses_or_interfaces(it, "FakeKotlinClass", fakeKotlinPackageId, it) }
        )
    val fakeKotlinTypeId: Label<DbKt_nullable_type> =
        tw.getLabelFor(
            "@\"FakeKotlinType\"",
            { tw.writeKt_nullable_types(it, fakeKotlinClassId) }
        )
    return fakeKotlinTypeId
}

/*
OLD: KE1
    // `args` can be null to describe a raw generic type.
    // For non-generic types it will be zero-length list.
    fun useSimpleTypeClass(
        c: IrClass,
        args: List<IrTypeArgument>?,
        hasQuestionMark: Boolean
    ): TypeResults {
        val classInstanceResult = useClassInstance(c, args)
        val javaClassId = classInstanceResult.typeResult.id
        val kotlinQualClassName = getUnquotedClassLabel(c, args).classLabel
        val javaResult = classInstanceResult.typeResult
        val kotlinResult =
            if (true) TypeResult(fakeKotlinType(), "TODO", "TODO")
            else if (hasQuestionMark) {
                val kotlinSignature = "$kotlinQualClassName?" // TODO: Is this right?
                val kotlinLabel = "@\"kt_type;nullable;$kotlinQualClassName\""
                val kotlinId: Label<DbKt_nullable_type> =
                    tw.getLabelFor(kotlinLabel, { tw.writeKt_nullable_types(it, javaClassId) })
                TypeResult(kotlinId, kotlinSignature, "TODO")
            } else {
                val kotlinSignature = kotlinQualClassName // TODO: Is this right?
                val kotlinLabel = "@\"kt_type;notnull;$kotlinQualClassName\""
                val kotlinId: Label<DbKt_notnull_type> =
                    tw.getLabelFor(kotlinLabel, { tw.writeKt_notnull_types(it, javaClassId) })
                TypeResult(kotlinId, kotlinSignature, "TODO")
            }
        return TypeResults(javaResult, kotlinResult)
    }
*/

enum class TypeContext {
    RETURN,
    GENERIC_ARGUMENT,
    OTHER
}

/*
OLD: KE1
    private fun useSimpleType(s: IrSimpleType, context: TypeContext): TypeResults {
        if (s.abbreviation != null) {
            // TODO: Extract this information
        }
        // We use this when we don't actually have an IrClass for a class
        // we want to refer to
        // TODO: Eliminate the need for this if possible
        fun makeClass(pkgName: String, className: String): Label<DbClassorinterface> {
            val pkgId = extractPackage(pkgName)
            val label = "@\"class;$pkgName.$className\""
            val classId: Label<DbClassorinterface> =
                tw.getLabelFor(label, { tw.writeClasses_or_interfaces(it, className, pkgId, it) })
            return classId
        }
        fun primitiveType(
            kotlinClass: IrClass,
            primitiveName: String?,
            otherIsPrimitive: Boolean,
            javaClass: IrClass,
            kotlinPackageName: String,
            kotlinClassName: String
        ): TypeResults {
            // Note the use of `hasEnhancedNullability` here covers cases like `@NotNull Integer`,
            // which must be extracted as `Integer` not `int`.
            val javaResult =
                if (
                    (context == TypeContext.RETURN ||
                        (context == TypeContext.OTHER && otherIsPrimitive)) &&
                        !s.isNullable() &&
                        getKotlinType(s)?.hasEnhancedNullability() != true &&
                        primitiveName != null
                ) {
                    val label: Label<DbPrimitive> =
                        tw.getLabelFor(
                            "@\"type;$primitiveName\"",
                            { tw.writePrimitives(it, primitiveName) }
                        )
                    TypeResult(label, primitiveName, primitiveName)
                } else {
                    addClassLabel(javaClass, listOf())
                }
            val kotlinClassId = useClassInstance(kotlinClass, listOf()).typeResult.id
            val kotlinResult =
                if (true) TypeResult(fakeKotlinType(), "TODO", "TODO")
                else if (s.isNullable()) {
                    val kotlinSignature =
                        "$kotlinPackageName.$kotlinClassName?" // TODO: Is this right?
                    val kotlinLabel = "@\"kt_type;nullable;$kotlinPackageName.$kotlinClassName\""
                    val kotlinId: Label<DbKt_nullable_type> =
                        tw.getLabelFor(
                            kotlinLabel,
                            { tw.writeKt_nullable_types(it, kotlinClassId) }
                        )
                    TypeResult(kotlinId, kotlinSignature, "TODO")
                } else {
                    val kotlinSignature =
                        "$kotlinPackageName.$kotlinClassName" // TODO: Is this right?
                    val kotlinLabel = "@\"kt_type;notnull;$kotlinPackageName.$kotlinClassName\""
                    val kotlinId: Label<DbKt_notnull_type> =
                        tw.getLabelFor(kotlinLabel, { tw.writeKt_notnull_types(it, kotlinClassId) })
                    TypeResult(kotlinId, kotlinSignature, "TODO")
                }
            return TypeResults(javaResult, kotlinResult)
        }

        val owner = s.classifier.owner
        val primitiveInfo = primitiveTypeMapping.getPrimitiveInfo(s)

        when {
            primitiveInfo != null -> {
                if (owner is IrClass) {
                    return primitiveType(
                        owner,
                        primitiveInfo.primitiveName,
                        primitiveInfo.otherIsPrimitive,
                        primitiveInfo.javaClass,
                        primitiveInfo.kotlinPackageName,
                        primitiveInfo.kotlinClassName
                    )
                } else {
                    logger.error(
                        "Got primitive info for non-class (${owner.javaClass}) for ${s.render()}"
                    )
                    return extractErrorType()
                }
            }
            (s.isBoxedArray && s.arguments.isNotEmpty()) || s.isPrimitiveArray() -> {
                val arrayInfo = useArrayType(s, false)
                return arrayInfo.componentTypeResults
            }
            owner is IrClass -> {
                val args = if (s.isRawType()) null else s.arguments

                return useSimpleTypeClass(owner, args, s.isNullable())
            }
            owner is IrTypeParameter -> {
                val javaResult = useTypeParameter(owner)
                val aClassId = makeClass("kotlin", "TypeParam") // TODO: Wrong
                val kotlinResult =
                    if (true) TypeResult(fakeKotlinType(), "TODO", "TODO")
                    else if (s.isNullable()) {
                        val kotlinSignature = "${javaResult.signature}?" // TODO: Wrong
                        val kotlinLabel = "@\"kt_type;nullable;type_param\"" // TODO: Wrong
                        val kotlinId: Label<DbKt_nullable_type> =
                            tw.getLabelFor(kotlinLabel, { tw.writeKt_nullable_types(it, aClassId) })
                        TypeResult(kotlinId, kotlinSignature, "TODO")
                    } else {
                        val kotlinSignature = javaResult.signature // TODO: Wrong
                        val kotlinLabel = "@\"kt_type;notnull;type_param\"" // TODO: Wrong
                        val kotlinId: Label<DbKt_notnull_type> =
                            tw.getLabelFor(kotlinLabel, { tw.writeKt_notnull_types(it, aClassId) })
                        TypeResult(kotlinId, kotlinSignature, "TODO")
                    }
                return TypeResults(javaResult, kotlinResult)
            }
            else -> {
                logger.error("Unrecognised IrSimpleType: " + s.javaClass + ": " + s.render())
                return extractErrorType()
            }
        }
    }
*/

