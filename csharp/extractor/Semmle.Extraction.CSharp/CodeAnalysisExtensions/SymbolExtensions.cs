using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using Microsoft.CodeAnalysis;
using Semmle.Extraction.CSharp.Entities;

namespace Semmle.Extraction.CSharp
{
    /// <summary>
    /// An ITypeSymbol with nullability annotations.
    /// Although a similar class has been implemented in Roslyn,
    /// https://github.com/dotnet/roslyn/blob/090e52e27c38ad8f1ea4d033114c2a107604ddaa/src/Compilers/CSharp/Portable/Symbols/TypeWithAnnotations.cs
    /// it is an internal struct that has not yet been exposed on the public interface.
    /// </summary>
    public struct AnnotatedTypeSymbol
    {
        public ITypeSymbol? Symbol { get; set; }
        public NullableAnnotation Nullability { get; }

        public AnnotatedTypeSymbol(ITypeSymbol? symbol, NullableAnnotation nullability)
        {
            Symbol = symbol;
            Nullability = nullability;
        }

        public static AnnotatedTypeSymbol? CreateNotAnnotated(ITypeSymbol? symbol) =>
            symbol is null ? (AnnotatedTypeSymbol?)null : new AnnotatedTypeSymbol(symbol, NullableAnnotation.None);
    }

    internal static class AnnotatedTypeSymbolExtensions
    {
        /// <summary>
        /// Returns true if the type is a string type.
        /// </summary>
        public static bool IsStringType(this AnnotatedTypeSymbol? type) =>
            type.HasValue && type.Value.Symbol?.SpecialType == SpecialType.System_String;
    }

    internal static class SymbolExtensions
    {
        /// <summary>
        /// Tries to recover from an ErrorType.
        /// </summary>
        ///
        /// <param name="type">The type to disambiguate.</param>
        /// <returns></returns>
        public static ITypeSymbol? DisambiguateType(this ITypeSymbol? type)
        {
            /* A type could not be determined.
             * Sometimes this happens due to a missing reference,
             * or sometimes because the same type is defined in multiple places.
             *
             * In the case that a symbol is multiply-defined, Roslyn tells you which
             * symbols are candidates. It usually resolves to the same DB entity,
             * so it's reasonably safe to just pick a candidate.
             *
             * The conservative option would be to resolve all error types as null.
             */

            return type is IErrorTypeSymbol errorType && errorType.CandidateSymbols.Any()
                ? errorType.CandidateSymbols.First() as ITypeSymbol
                : type;
        }

        private static IEnumerable<SyntaxToken> GetModifiers<T>(this ISymbol symbol, Func<T, IEnumerable<SyntaxToken>> getModifierTokens) =>
            symbol.DeclaringSyntaxReferences
                .Select(r => r.GetSyntax())
                .OfType<T>()
                .SelectMany(getModifierTokens);

        /// <summary>
        /// Gets the source-level modifiers belonging to this symbol, if any.
        /// </summary>
        public static IEnumerable<string> GetSourceLevelModifiers(this ISymbol symbol) =>
            symbol.GetModifiers<Microsoft.CodeAnalysis.CSharp.Syntax.MemberDeclarationSyntax>(md => md.Modifiers).Select(m => m.Text);

        /// <summary>
        /// Holds if the ID generated for `dependant` will contain a reference to
        /// the ID for `symbol`. If this is the case, then the ID for `symbol` must
        /// not contain a reference back to `dependant`.
        /// </summary>
        public static bool IdDependsOn(this ITypeSymbol dependant, Context cx, ISymbol symbol)
        {
            var seen = new HashSet<ITypeSymbol>(SymbolEqualityComparer.Default);

            bool IdDependsOnImpl(ITypeSymbol? type)
            {
                if (SymbolEqualityComparer.Default.Equals(type, symbol))
                    return true;

                if (type is null || seen.Contains(type))
                    return false;

                seen.Add(type);

                using (cx.StackGuard)
                {
                    switch (type.TypeKind)
                    {
                        case TypeKind.Array:
                            var array = (IArrayTypeSymbol)type;
                            return IdDependsOnImpl(array.ElementType);
                        case TypeKind.Class:
                        case TypeKind.Interface:
                        case TypeKind.Struct:
                        case TypeKind.Enum:
                        case TypeKind.Delegate:
                        case TypeKind.Error:
                            var named = (INamedTypeSymbol)type;
                            if (named.IsTupleType && named.TupleUnderlyingType is not null)
                                named = named.TupleUnderlyingType;
                            if (IdDependsOnImpl(named.ContainingType))
                                return true;
                            if (IdDependsOnImpl(named.ConstructedFrom))
                                return true;
                            return named.TypeArguments.Any(IdDependsOnImpl);
                        case TypeKind.Pointer:
                            var ptr = (IPointerTypeSymbol)type;
                            return IdDependsOnImpl(ptr.PointedAtType);
                        case TypeKind.TypeParameter:
                            var tp = (ITypeParameterSymbol)type;
                            return tp.ContainingSymbol is ITypeSymbol cont
                                ? IdDependsOnImpl(cont)
                                : SymbolEqualityComparer.Default.Equals(tp.ContainingSymbol, symbol);
                        case TypeKind.FunctionPointer:
                            var funptr = (IFunctionPointerTypeSymbol)type;
                            if (funptr.Signature.Parameters.Any(p => IdDependsOnImpl(p.Type)))
                            {
                                return true;
                            }
                            return IdDependsOnImpl(funptr.Signature.ReturnType);
                        default:
                            return false;
                    }
                }
            }

            return IdDependsOnImpl(dependant);
        }

        /// <summary>
        /// Constructs a unique string for this type symbol.
        /// </summary>
        /// <param name="cx">The extraction context.</param>
        /// <param name="trapFile">The trap builder used to store the result.</param>
        /// <param name="symbolBeingDefined">The outer symbol being defined (to avoid recursive ids).</param>
        /// <param name="constructUnderlyingTupleType">Whether to build a type ID for the underlying `System.ValueTuple` struct in the case of tuple types.</param>
        public static void BuildTypeId(this ITypeSymbol type, Context cx, EscapingTextWriter trapFile, ISymbol symbolBeingDefined, bool constructUnderlyingTupleType)
        {
            using (cx.StackGuard)
            {
                switch (type.TypeKind)
                {
                    case TypeKind.Array:
                        var array = (IArrayTypeSymbol)type;
                        array.ElementType.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType: false);
                        array.BuildArraySuffix(trapFile);
                        return;
                    case TypeKind.Class:
                    case TypeKind.Interface:
                    case TypeKind.Struct:
                    case TypeKind.Enum:
                    case TypeKind.Delegate:
                    case TypeKind.Error:
                        var named = (INamedTypeSymbol)type;
                        named.BuildNamedTypeId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType);
                        return;
                    case TypeKind.Pointer:
                        var ptr = (IPointerTypeSymbol)type;
                        ptr.PointedAtType.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType: false);
                        trapFile.Write('*');
                        return;
                    case TypeKind.TypeParameter:
                        var tp = (ITypeParameterSymbol)type;
                        tp.ContainingSymbol.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType: false);
                        trapFile.Write('_');
                        trapFile.Write(tp.Name);
                        return;
                    case TypeKind.Dynamic:
                        trapFile.Write("dynamic");
                        return;
                    case TypeKind.FunctionPointer:
                        var funptr = (IFunctionPointerTypeSymbol)type;
                        funptr.BuildFunctionPointerTypeId(cx, trapFile, symbolBeingDefined);
                        return;
                    default:
                        throw new InternalError(type, $"Unhandled type kind '{type.TypeKind}'");
                }
            }
        }

        private static void BuildOrWriteId(this ISymbol? symbol, Context cx, EscapingTextWriter trapFile, ISymbol symbolBeingDefined, bool constructUnderlyingTupleType)
        {
            if (symbol is null)
            {
                cx.ModelError(symbolBeingDefined, "Missing symbol. Couldn't build some part of the ID.");
                return;
            }

            // We need to keep track of the symbol being defined in order to avoid cyclic labels.
            // For example, in
            //
            // ```csharp
            // class C<T> : IEnumerable<T> { }
            // ```
            //
            // when we generate the label for ``C`1``, the base class `IEnumerable<T>` has `T` as a type
            // argument, which will be qualified with `__self__` instead of the label we are defining.
            // In effect, the label will (simplified) look like
            //
            // ```
            // #123 = @"C`1 : IEnumerable<__self___T>"
            // ```
            if (SymbolEqualityComparer.Default.Equals(symbol, symbolBeingDefined))
                trapFile.Write("__self__");
            else if (symbol is ITypeSymbol type && type.IdDependsOn(cx, symbolBeingDefined))
                type.BuildTypeId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType);
            else if (symbol is INamedTypeSymbol namedType && namedType.IsTupleType && constructUnderlyingTupleType)
                trapFile.WriteSubId(NamedType.CreateNamedTypeFromTupleType(cx, namedType));
            else
                trapFile.WriteSubId(CreateEntity(cx, symbol));
        }

        /// <summary>
        /// Adds an appropriate ID to the trap builder <paramref name="trapFile"/>
        /// for the symbol <paramref name="symbol"/> belonging to
        /// <paramref name="symbolBeingDefined"/>.
        ///
        /// This will either write a reference to the ID of the entity belonging to
        /// <paramref name="symbol"/> (`{#label}`), or if that will lead to cyclic IDs,
        /// it will generate an appropriate ID that encodes the signature of
        /// <paramref name="symbol" />.
        /// </summary>
        public static void BuildOrWriteId(this ISymbol? symbol, Context cx, EscapingTextWriter trapFile, ISymbol symbolBeingDefined) =>
            symbol.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType: false);

        /// <summary>
        /// Constructs an array suffix string for this array type symbol.
        /// </summary>
        /// <param name="trapFile">The trap builder used to store the result.</param>
        public static void BuildArraySuffix(this IArrayTypeSymbol array, TextWriter trapFile)
        {
            trapFile.Write('[');
            for (var i = 0; i < array.Rank - 1; i++)
                trapFile.Write(',');
            trapFile.Write(']');
        }

        private static void BuildAssembly(IAssemblySymbol asm, EscapingTextWriter trapFile, bool extraPrecise = false)
        {
            var assembly = asm.Identity;
            trapFile.Write(assembly.Name);
            trapFile.Write('_');
            trapFile.Write(assembly.Version.Major);
            trapFile.Write('.');
            trapFile.Write(assembly.Version.Minor);
            trapFile.Write('.');
            trapFile.Write(assembly.Version.Build);
            if (extraPrecise)
            {
                trapFile.Write('.');
                trapFile.Write(assembly.Version.Revision);
            }
            trapFile.Write("::");
        }

        private static void BuildFunctionPointerTypeId(this IFunctionPointerTypeSymbol funptr, Context cx, EscapingTextWriter trapFile, ISymbol symbolBeingDefined) =>
            BuildFunctionPointerSignature(funptr, trapFile, s => s.BuildOrWriteId(cx, trapFile, symbolBeingDefined));

        /// <summary>
        /// Workaround for a Roslyn bug: https://github.com/dotnet/roslyn/issues/53943
        /// </summary>
        public static IEnumerable<IFieldSymbol?> GetTupleElementsMaybeNull(this INamedTypeSymbol type) =>
            type.TupleElements;

        private static void BuildQualifierAndName(INamedTypeSymbol named, Context cx, EscapingTextWriter trapFile, ISymbol symbolBeingDefined)
        {
            if (named.ContainingType is not null)
            {
                named.ContainingType.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType: false);
                trapFile.Write('.');
            }
            else if (named.ContainingNamespace is not null)
            {
                if (cx.ShouldAddAssemblyTrapPrefix && named.ContainingAssembly is not null)
                    BuildAssembly(named.ContainingAssembly, trapFile);
                named.ContainingNamespace.BuildNamespace(cx, trapFile);
            }

            var name = named.IsFileLocal ? named.MetadataName : named.Name;
            trapFile.Write(name);
        }

        private static void BuildTupleId(INamedTypeSymbol named, Context cx, EscapingTextWriter trapFile, ISymbol symbolBeingDefined)
        {
            trapFile.Write('(');
            trapFile.BuildList(",", named.GetTupleElementsMaybeNull(),
                (i, f) =>
                {
                    if (f is null)
                    {
                        trapFile.Write($"null({i})");
                    }
                    else
                    {
                        trapFile.Write((f.CorrespondingTupleField ?? f).Name);
                        trapFile.Write(":");
                        f.Type.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType: false);
                    }
                }
                );
            trapFile.Write(")");
        }

        private static void BuildNamedTypeId(this INamedTypeSymbol named, Context cx, EscapingTextWriter trapFile, ISymbol symbolBeingDefined, bool constructUnderlyingTupleType)
        {
            if (!constructUnderlyingTupleType && named.IsTupleType)
            {
                BuildTupleId(named, cx, trapFile, symbolBeingDefined);
                return;
            }

            if (named.TypeParameters.IsEmpty)
            {
                BuildQualifierAndName(named, cx, trapFile, symbolBeingDefined);
            }
            else if (named.IsReallyUnbound())
            {
                BuildQualifierAndName(named, cx, trapFile, symbolBeingDefined);
                trapFile.Write("`");
                trapFile.Write(named.TypeParameters.Length);
            }
            else
            {
                named.ConstructedFrom.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType);
                trapFile.Write('<');
                // Encode the nullability of the type arguments in the label.
                // Type arguments with different nullability can result in
                // a constructed type with different nullability of its members and methods,
                // so we need to create a distinct database entity for it.
                trapFile.BuildList(",", named.GetAnnotatedTypeArguments(),
                    ta => ta.Symbol.BuildOrWriteId(cx, trapFile, symbolBeingDefined, constructUnderlyingTupleType: false)
                    );
                trapFile.Write('>');
            }
        }

        private static void BuildNamespace(this INamespaceSymbol ns, Context cx, EscapingTextWriter trapFile)
        {
            trapFile.WriteSubId(Namespace.Create(cx, ns));
            trapFile.Write('.');
        }

        private static void BuildAnonymousName(this INamedTypeSymbol type, Context cx, TextWriter trapFile)
        {
            var memberCount = type.GetMembers().OfType<IPropertySymbol>().Count();
            var hackTypeNumber = memberCount == 1 ? 1 : 0;
            trapFile.Write("<>__AnonType");
            trapFile.Write(hackTypeNumber);
            trapFile.Write('<');
            trapFile.BuildList(",", type.GetMembers().OfType<IPropertySymbol>(), prop => BuildDisplayName(prop.Type, cx, trapFile));
            trapFile.Write('>');
        }

        /// <summary>
        /// Constructs a display name string for this type symbol.
        /// </summary>
        /// <param name="trapFile">The trap builder used to store the result.</param>
        public static void BuildDisplayName(this ITypeSymbol type, Context cx, TextWriter trapFile, bool constructUnderlyingTupleType = false)
        {
            using (cx.StackGuard)
            {
                switch (type.TypeKind)
                {
                    case TypeKind.Array:
                        var array = (IArrayTypeSymbol)type;
                        var elementType = array.ElementType;
                        if (elementType.MetadataName.Contains("`"))
                        {
                            trapFile.Write(TrapExtensions.EncodeString(elementType.Name));
                            return;
                        }
                        elementType.BuildDisplayName(cx, trapFile);
                        array.BuildArraySuffix(trapFile);
                        return;
                    case TypeKind.Class:
                    case TypeKind.Interface:
                    case TypeKind.Struct:
                    case TypeKind.Enum:
                    case TypeKind.Delegate:
                    case TypeKind.Error:
                        var named = (INamedTypeSymbol)type;
                        named.BuildNamedTypeDisplayName(cx, trapFile, constructUnderlyingTupleType);
                        return;
                    case TypeKind.Pointer:
                        var ptr = (IPointerTypeSymbol)type;
                        ptr.PointedAtType.BuildDisplayName(cx, trapFile);
                        trapFile.Write('*');
                        return;
                    case TypeKind.FunctionPointer:
                        var funptr = (IFunctionPointerTypeSymbol)type;
                        funptr.BuildFunctionPointerTypeDisplayName(cx, trapFile);
                        return;
                    case TypeKind.TypeParameter:
                        trapFile.Write(type.Name);
                        return;
                    case TypeKind.Dynamic:
                        trapFile.Write("dynamic");
                        return;
                    default:
                        throw new InternalError(type, $"Unhandled type kind '{type.TypeKind}'");
                }
            }
        }

        public static void BuildFunctionPointerSignature(IFunctionPointerTypeSymbol funptr, TextWriter trapFile,
            Action<ITypeSymbol> buildNested)
        {
            trapFile.Write("delegate* ");
            trapFile.Write(funptr.Signature.CallingConvention.ToString().ToLowerInvariant());

            if (funptr.Signature.UnmanagedCallingConventionTypes.Any())
            {
                trapFile.Write('[');
                trapFile.BuildList(",", funptr.Signature.UnmanagedCallingConventionTypes, buildNested);
                trapFile.Write("]");
            }

            trapFile.Write('<');
            trapFile.BuildList(",", funptr.Signature.Parameters,
                p =>
                {
                    buildNested(p.Type);
                    switch (p.RefKind)
                    {
                        case RefKind.Out:
                            trapFile.Write(" out");
                            break;
                        case RefKind.In:
                            trapFile.Write(" in");
                            break;
                        case RefKind.Ref:
                            trapFile.Write(" ref");
                            break;
                    }
                });

            if (funptr.Signature.Parameters.Any())
            {
                trapFile.Write(",");
            }

            buildNested(funptr.Signature.ReturnType);

            if (funptr.Signature.ReturnsByRef)
                trapFile.Write(" ref");
            if (funptr.Signature.ReturnsByRefReadonly)
                trapFile.Write(" ref readonly");

            trapFile.Write('>');
        }

        private static void BuildFunctionPointerTypeDisplayName(this IFunctionPointerTypeSymbol funptr, Context cx, TextWriter trapFile) =>
            BuildFunctionPointerSignature(funptr, trapFile, s => s.BuildDisplayName(cx, trapFile));

        private static void BuildNamedTypeDisplayName(this INamedTypeSymbol namedType, Context cx, TextWriter trapFile, bool constructUnderlyingTupleType)
        {
            if (!constructUnderlyingTupleType && namedType.IsTupleType)
            {
                trapFile.Write('(');
                trapFile.BuildList(
                    ",",
                    namedType.GetTupleElementsMaybeNull(),
                    (i, f) =>
                    {
                        if (f is null)
                            trapFile.Write($"null({i})");
                        else
                            f.Type.BuildDisplayName(cx, trapFile);
                    });
                trapFile.Write(")");
                return;
            }

            if (namedType.IsAnonymousType)
            {
                namedType.BuildAnonymousName(cx, trapFile);
            }
            else
            {
                trapFile.Write(TrapExtensions.EncodeString(namedType.Name));
            }
        }

        public static bool IsReallyUnbound(this INamedTypeSymbol type) =>
            SymbolEqualityComparer.Default.Equals(type.ConstructedFrom, type) || type.IsUnboundGenericType;

        public static bool IsReallyBound(this INamedTypeSymbol type) => !IsReallyUnbound(type);

        /// <summary>
        /// Holds if this type is of the form <code>int?</code> or
        /// <code>System.Nullable&lt;int&gt;</code>.
        /// </summary>
        public static bool IsBoundNullable(this ITypeSymbol type) =>
            type.SpecialType == SpecialType.None && type.OriginalDefinition.IsUnboundNullable();

        /// <summary>
        /// Holds if this type is <code>System.Nullable&lt;T&gt;</code>.
        /// </summary>
        public static bool IsUnboundNullable(this ITypeSymbol type) =>
            type.SpecialType == SpecialType.System_Nullable_T;

        /// <summary>
        /// Holds if this type is <code>System.Span&lt;T&gt;</code>.
        /// </summary>
        public static bool IsUnboundSpan(this ITypeSymbol type) =>
            type.ToString() == "System.Span<T>";

        /// <summary>
        /// Holds if this type is of the form <code>System.Span&lt;byte&gt;</code>.
        /// </summary>
        public static bool IsBoundSpan(this ITypeSymbol type) =>
            type.SpecialType == SpecialType.None && type.OriginalDefinition.IsUnboundSpan();

        /// <summary>
        /// Holds if this type is <code>System.ReadOnlySpan&lt;T&gt;</code>.
        /// </summary>
        public static bool IsUnboundReadOnlySpan(this ITypeSymbol type) =>
            type.ToString() == "System.ReadOnlySpan<T>";

        public static bool IsInlineArray(this ITypeSymbol type)
        {
            var attributes = type.GetAttributes();
            var isInline = attributes.Any(attribute =>
                    attribute.AttributeClass is INamedTypeSymbol nt &&
                    nt.Name == "InlineArrayAttribute" &&
                    nt.ContainingNamespace.ToString() == "System.Runtime.CompilerServices"
            );
            return isInline;
        }

        /// <summary>
        /// Returns true if this type implements `System.IFormattable`.
        /// </summary>
        public static bool ImplementsIFormattable(this ITypeSymbol type) =>
            type.AllInterfaces.Any(i => i.Name == "IFormattable" && i.ContainingNamespace.ToString() == "System");

        /// <summary>
        /// Holds if this type is of the form <code>System.ReadOnlySpan&lt;byte&gt;</code>.
        /// </summary>
        public static bool IsBoundReadOnlySpan(this ITypeSymbol type) =>
            type.SpecialType == SpecialType.None && type.OriginalDefinition.IsUnboundReadOnlySpan();

        /// <summary>
        /// Gets the parameters of a method or property.
        /// </summary>
        /// <returns>The list of parameters, or an empty list.</returns>
        public static IEnumerable<IParameterSymbol> GetParameters(this ISymbol parameterizable)
        {
            if (parameterizable is IMethodSymbol meth)
                return meth.Parameters;

            if (parameterizable is IPropertySymbol prop)
                return prop.Parameters;

            return Enumerable.Empty<IParameterSymbol>();
        }

        /// <summary>
        /// Holds if this symbol is defined in a source code file.
        /// </summary>
        public static bool FromSource(this ISymbol symbol) => symbol.Locations.Any(l => l.IsInSource);

        /// <summary>
        /// Holds if this symbol is a source declaration.
        /// </summary>
        public static bool IsSourceDeclaration(this ISymbol symbol) => SymbolEqualityComparer.Default.Equals(symbol, symbol.OriginalDefinition);

        /// <summary>
        /// Holds if this method is a source declaration.
        /// </summary>
        public static bool IsSourceDeclaration(this IMethodSymbol method) =>
            IsSourceDeclaration((ISymbol)method) && SymbolEqualityComparer.Default.Equals(method, method.ConstructedFrom) && method.ReducedFrom is null;

        /// <summary>
        /// Holds if this parameter is a source declaration.
        /// </summary>
        public static bool IsSourceDeclaration(this IParameterSymbol parameter)
        {
            if (parameter.ContainingSymbol is IMethodSymbol method)
                return method.IsSourceDeclaration();
            if (parameter.ContainingSymbol is IPropertySymbol property && property.IsIndexer)
                return property.IsSourceDeclaration();
            return true;
        }

        /// <summary>
        /// Gets the base type of `symbol`. Unlike `symbol.BaseType`, this excludes effective base
        /// types of type parameters as well as `object` base types.
        /// </summary>
        public static INamedTypeSymbol? GetNonObjectBaseType(this ITypeSymbol symbol, Context cx) =>
            symbol is ITypeParameterSymbol || SymbolEqualityComparer.Default.Equals(symbol.BaseType, cx.Compilation.ObjectType) ? null : symbol.BaseType;

        [return: NotNullIfNotNull(nameof(symbol))]
        public static IEntity? CreateEntity(this Context cx, ISymbol symbol)
        {
            if (symbol is null)
                return null;

            using (cx.StackGuard)
            {
                try
                {
                    var entity = symbol.Accept(new Populators.Symbols(cx));
                    if (entity is null)
                    {
                        cx.ModelError(symbol, $"Symbol visitor returned null entity on symbol: {symbol}");
                    }
#nullable disable warnings
                    return entity;
#nullable restore warnings
                }
                catch (Exception ex)  // lgtm[cs/catch-of-all-exceptions]
                {
                    cx.ModelError(symbol, $"Exception processing symbol '{symbol.Kind}' of type '{ex}': {symbol}");
#nullable disable warnings
                    return null;
#nullable restore warnings
                }
            }
        }

        public static TypeInfo GetTypeInfo(this Context cx, Microsoft.CodeAnalysis.CSharp.CSharpSyntaxNode node) =>
            cx.GetModel(node).GetTypeInfo(node);

        public static SymbolInfo GetSymbolInfo(this Context cx, Microsoft.CodeAnalysis.CSharp.CSharpSyntaxNode node) =>
            cx.GetModel(node).GetSymbolInfo(node);

        /// <summary>
        /// Determines the type of a node, or default
        /// if the type could not be determined.
        /// </summary>
        /// <param name="cx">Extractor context.</param>
        /// <param name="node">The node to determine.</param>
        /// <returns>The type symbol of the node, or default.</returns>
        public static AnnotatedTypeSymbol GetType(this Context cx, Microsoft.CodeAnalysis.CSharp.CSharpSyntaxNode node)
        {
            var info = GetTypeInfo(cx, node);
            return new AnnotatedTypeSymbol(info.Type.DisambiguateType(), info.Nullability.Annotation);
        }

        /// <summary>
        /// Gets the annotated type arguments of an INamedTypeSymbol.
        /// This has not yet been exposed on the public API.
        /// </summary>
        public static IEnumerable<AnnotatedTypeSymbol> GetAnnotatedTypeArguments(this INamedTypeSymbol symbol) =>
            symbol.TypeArguments.Zip(symbol.TypeArgumentNullableAnnotations, (t, a) => new AnnotatedTypeSymbol(t, a));

        /// <summary>
        /// Returns true if the symbol is public, protected or protected internal.
        /// </summary>
        public static bool IsPublicOrProtected(this ISymbol symbol) =>
            symbol.DeclaredAccessibility == Accessibility.Public
            || symbol.DeclaredAccessibility == Accessibility.Protected
            || symbol.DeclaredAccessibility == Accessibility.ProtectedOrInternal;

        /// <summary>
        /// Returns true if the given symbol should be extracted.
        /// </summary>
        public static bool ShouldExtractSymbol(this ISymbol symbol)
        {
            // Extract all source symbols and public/protected metadata symbols.
            if (symbol.Locations.Any(x => !x.IsInMetadata) || symbol.IsPublicOrProtected())
            {
                return true;
            }
            if (symbol is IMethodSymbol method)
            {
                return method.ExplicitInterfaceImplementations.Any(m => m.ContainingType.ShouldExtractSymbol());
            }
            if (symbol is IPropertySymbol property)
            {
                return property.ExplicitInterfaceImplementations.Any(m => m.ContainingType.ShouldExtractSymbol());
            }
            return false;
        }

        /// <summary>
        /// Returns the symbols that should be extracted.
        /// </summary>
        public static IEnumerable<T> ExtractionCandidates<T>(this IEnumerable<T> symbols) where T : ISymbol =>
            symbols.Where(symbol => symbol.ShouldExtractSymbol());
    }
}
