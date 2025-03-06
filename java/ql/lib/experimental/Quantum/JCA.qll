import java
import semmle.code.java.dataflow.DataFlow
import semmle.code.java.controlflow.Dominance

module JCAModel {
  import Language

  // TODO: Verify that the PBEWith% case works correctly
  bindingset[algo]
  predicate cipher_names(string algo) {
    algo.toUpperCase()
        .matches([
            "AES", "AESWrap", "AESWrapPad", "ARCFOUR", "Blowfish", "ChaCha20", "ChaCha20-Poly1305",
            "DES", "DESede", "DESedeWrap", "ECIES", "PBEWith%", "RC2", "RC4", "RC5", "RSA"
          ].toUpperCase())
  }

  // TODO: Verify that the CFB% case works correctly
  bindingset[mode]
  predicate cipher_modes(string mode) {
    mode.toUpperCase()
        .matches([
            "NONE", "CBC", "CCM", "CFB", "CFB%", "CTR", "CTS", "ECB", "GCM", "KW", "KWP", "OFB",
            "OFB%", "PCBC"
          ].toUpperCase())
  }

  // TODO: Verify that the OAEPWith% case works correctly
  bindingset[padding]
  predicate cipher_padding(string padding) {
    padding
        .toUpperCase()
        .matches([
            "NoPadding", "ISO10126Padding", "OAEPPadding", "OAEPWith%", "PKCS1Padding",
            "PKCS5Padding", "SSL3Padding"
          ].toUpperCase())
  }

  /**
   * A `StringLiteral` in the `"ALG/MODE/PADDING"` or `"ALG"` format
   */
  class CipherStringLiteral extends StringLiteral {
    CipherStringLiteral() { cipher_names(this.getValue().splitAt("/")) }

    string getAlgorithmName() { result = this.getValue().splitAt("/", 0) }

    string getMode() { result = this.getValue().splitAt("/", 1) }

    string getPadding() { result = this.getValue().splitAt("/", 2) }
  }

  class CipherGetInstanceCall extends Call {
    CipherGetInstanceCall() {
      this.getCallee().hasQualifiedName("javax.crypto", "Cipher", "getInstance")
    }

    Expr getAlgorithmArg() { result = this.getArgument(0) }

    Expr getProviderArg() { result = this.getArgument(1) }
  }

  private class CipherOperationCall extends MethodCall {
    CipherOperationCall() {
      exists(string s | s in ["doFinal", "wrap", "unwrap"] |
        this.getMethod().hasQualifiedName("javax.crypto", "Cipher", s)
      )
    }

    Expr getInput() { result = this.getArgument(0) }

    Expr getOutput() {
      result = this.getArgument(3)
      or
      this.getMethod().getReturnType().hasName("byte[]") and result = this
    }

    DataFlow::Node getMessageArg() { result.asExpr() = this.getInput() }
  }

  /**
   * Data-flow configuration modelling flow from a cipher string literal to a `CipherGetInstanceCall` argument.
   */
  private module AlgorithmStringToFetchConfig implements DataFlow::ConfigSig {
    predicate isSource(DataFlow::Node src) { src.asExpr() instanceof CipherStringLiteral }

    predicate isSink(DataFlow::Node sink) {
      exists(CipherGetInstanceCall call | sink.asExpr() = call.getAlgorithmArg())
    }
  }

  module AlgorithmStringToFetchFlow = DataFlow::Global<AlgorithmStringToFetchConfig>;

  /**
   * Note: padding and a mode of operation will only exist when the padding / mode (*and its type*) are determinable.
   * This is because the mode will always be specified alongside the algorithm and never independently.
   * Therefore, we can always assume that a determinable algorithm will have a determinable mode.
   *
   * In the case that only an algorithm is specified, e.g., "AES", the provider provides a default mode.
   *
   * TODO: Model the case of relying on a provider default, but alert on it as a bad practice.
   */
  class CipherStringLiteralAlgorithmInstance extends Crypto::CipherAlgorithmInstance,
    Crypto::ModeOfOperationAlgorithmInstance, Crypto::PaddingAlgorithmInstance instanceof CipherStringLiteral
  {
    CipherGetInstanceAlgorithmArg consumer;

    CipherStringLiteralAlgorithmInstance() {
      AlgorithmStringToFetchFlow::flow(DataFlow::exprNode(this), DataFlow::exprNode(consumer))
    }

    CipherGetInstanceAlgorithmArg getConsumer() { result = consumer }

    override Crypto::ModeOfOperationAlgorithmInstance getModeOfOperationAlgorithm() {
      result = this and exists(this.getRawModeAlgorithmName()) // TODO: provider defaults
    }

    override Crypto::PaddingAlgorithmInstance getPaddingAlgorithm() {
      result = this and exists(this.getRawPaddingAlgorithmName()) // TODO: provider defaults
    }

    override string getRawAlgorithmName() { result = super.getValue() }

    override Crypto::TCipherType getCipherFamily() {
      if this.cipherNameMappingKnown(_, super.getAlgorithmName())
      then this.cipherNameMappingKnown(result, super.getAlgorithmName())
      else result instanceof Crypto::OTHERCIPHERTYPE
    }

    bindingset[name]
    private predicate cipherNameMappingKnown(Crypto::TCipherType type, string name) {
      name = "AES" and
      type instanceof Crypto::AES
      or
      name = "DES" and
      type instanceof Crypto::DES
      or
      name = "TripleDES" and
      type instanceof Crypto::TRIPLEDES
      or
      name = "IDEA" and
      type instanceof Crypto::IDEA
      or
      name = "CAST5" and
      type instanceof Crypto::CAST5
      or
      name = "ChaCha20" and
      type instanceof Crypto::CHACHA20
      or
      name = "RC4" and
      type instanceof Crypto::RC4
      or
      name = "RC5" and
      type instanceof Crypto::RC5
      or
      name = "RSA" and
      type instanceof Crypto::RSA
    }

    private predicate modeToNameMappingKnown(Crypto::TBlockCipherModeOperationType type, string name) {
      type instanceof Crypto::ECB and name = "ECB"
      or
      type instanceof Crypto::CBC and name = "CBC"
      or
      type instanceof Crypto::GCM and name = "GCM"
      or
      type instanceof Crypto::CTR and name = "CTR"
      or
      type instanceof Crypto::XTS and name = "XTS"
      or
      type instanceof Crypto::CCM and name = "CCM"
      or
      type instanceof Crypto::SIV and name = "SIV"
      or
      type instanceof Crypto::OCB and name = "OCB"
    }

    override Crypto::TBlockCipherModeOperationType getModeType() {
      if this.modeToNameMappingKnown(_, super.getMode())
      then this.modeToNameMappingKnown(result, super.getMode())
      else result instanceof Crypto::OtherMode
    }

    override string getRawModeAlgorithmName() { result = super.getMode() }

    override string getRawPaddingAlgorithmName() { result = super.getPadding() }

    bindingset[name]
    private predicate paddingToNameMappingKnown(Crypto::TPaddingType type, string name) {
      type instanceof Crypto::NoPadding and name = "NOPADDING"
      or
      type instanceof Crypto::PKCS7 and name = ["PKCS5Padding", "PKCS7Padding"] // TODO: misnomer in the JCA?
      or
      type instanceof Crypto::OAEP and name.matches("OAEP%") // TODO: handle OAEPWith%
    }

    override Crypto::TPaddingType getPaddingType() {
      if this.paddingToNameMappingKnown(_, super.getPadding())
      then this.paddingToNameMappingKnown(result, super.getPadding())
      else result instanceof Crypto::OtherPadding
    }
  }

  /**
   * The cipher algorithm argument to a `CipherGetInstanceCall`.
   *
   * For example, in `Cipher.getInstance(algorithm)`, this class represents `algorithm`.
   */
  class CipherGetInstanceAlgorithmArg extends Crypto::AlgorithmConsumer instanceof Expr {
    CipherGetInstanceCall call;

    CipherGetInstanceAlgorithmArg() { this = call.getAlgorithmArg() }

    override DataFlow::Node getInputNode() { result.asExpr() = this }

    CipherStringLiteral getOrigin(string value) {
      AlgorithmStringToFetchFlow::flow(DataFlow::exprNode(result),
        DataFlow::exprNode(this.(Expr).getAChildExpr*())) and
      value = result.getValue()
    }

    override Crypto::AlgorithmElement getAKnownAlgorithmSource() {
      result.(CipherStringLiteralAlgorithmInstance).getConsumer() = this
    }
  }

  /**
   * An access to the `javax.crypto.Cipher` class.
   */
  private class CipherAccess extends TypeAccess {
    CipherAccess() { this.getType().(Class).hasQualifiedName("javax.crypto", "Cipher") }
  }

  /**
   * An access to a cipher mode field of the `javax.crypto.Cipher` class,
   * specifically `ENCRYPT_MODE`, `DECRYPT_MODE`, `WRAP_MODE`, or `UNWRAP_MODE`.
   */
  private class JavaxCryptoCipherOperationModeAccess extends FieldAccess {
    JavaxCryptoCipherOperationModeAccess() {
      this.getQualifier() instanceof CipherAccess and
      this.getField().getName().toUpperCase() in [
          "ENCRYPT_MODE", "DECRYPT_MODE", "WRAP_MODE", "UNWRAP_MODE"
        ]
    }
  }

  private newtype TCipherModeFlowState =
    TUninitializedCipherModeFlowState() or
    TInitializedCipherModeFlowState(CipherInitCall call) or
    TUsedCipherModeFlowState(CipherInitCall init)

  abstract private class CipherModeFlowState extends TCipherModeFlowState {
    string toString() {
      this = TUninitializedCipherModeFlowState() and result = "uninitialized"
      or
      this = TInitializedCipherModeFlowState(_) and result = "initialized"
    }

    abstract Crypto::CipherOperationSubtype getCipherOperationMode();
  }

  private class UninitializedCipherModeFlowState extends CipherModeFlowState,
    TUninitializedCipherModeFlowState
  {
    override Crypto::CipherOperationSubtype getCipherOperationMode() {
      result instanceof Crypto::UnknownCipherOperationSubtype
    }
  }

  private class InitializedCipherModeFlowState extends CipherModeFlowState,
    TInitializedCipherModeFlowState
  {
    CipherInitCall call;
    DataFlow::Node node1;
    DataFlow::Node node2;
    Crypto::CipherOperationSubtype mode;

    InitializedCipherModeFlowState() {
      this = TInitializedCipherModeFlowState(call) and
      DataFlow::localFlowStep(node1, node2) and
      node2.asExpr() = call.getQualifier() and
      // TODO: does this make this predicate inefficient as it binds with anything?
      not node1.asExpr() = call.getQualifier() and
      mode = call.getCipherOperationModeType()
    }

    CipherInitCall getInitCall() { result = call }

    DataFlow::Node getFstNode() { result = node1 }

    /**
     * Returns the node *to* which the state-changing step occurs
     */
    DataFlow::Node getSndNode() { result = node2 }

    override Crypto::CipherOperationSubtype getCipherOperationMode() { result = mode }
  }

  /**
   * Trace from cipher initialization to a cryptographic operation,
   * specifically `Cipher.doFinal()`, `Cipher.wrap()`, or `Cipher.unwrap()`.
   *
   * TODO: handle `Cipher.update()`
   */
  private module CipherGetInstanceToCipherOperationConfig implements DataFlow::StateConfigSig {
    class FlowState = TCipherModeFlowState;

    predicate isSource(DataFlow::Node src, FlowState state) {
      state instanceof UninitializedCipherModeFlowState and
      src.asExpr() instanceof CipherGetInstanceCall
    }

    predicate isSink(DataFlow::Node sink, FlowState state) { none() }

    predicate isSink(DataFlow::Node sink) {
      exists(CipherOperationCall c | c.getQualifier() = sink.asExpr())
    }

    predicate isAdditionalFlowStep(
      DataFlow::Node node1, FlowState state1, DataFlow::Node node2, FlowState state2
    ) {
      state1 = state1 and
      node1 = state2.(InitializedCipherModeFlowState).getFstNode() and
      node2 = state2.(InitializedCipherModeFlowState).getSndNode()
    }

    predicate isBarrier(DataFlow::Node node, FlowState state) {
      exists(CipherInitCall call | node.asExpr() = call.getQualifier() |
        state instanceof UninitializedCipherModeFlowState
        or
        state.(InitializedCipherModeFlowState).getInitCall() != call
      )
    }
  }

  module CipherGetInstanceToCipherOperationFlow =
    DataFlow::GlobalWithState<CipherGetInstanceToCipherOperationConfig>;

  class CipherOperationInstance extends Crypto::CipherOperationInstance instanceof Call {
    Crypto::CipherOperationSubtype mode;
    CipherGetInstanceToCipherOperationFlow::PathNode sink;
    CipherOperationCall doFinalize;
    CipherGetInstanceAlgorithmArg consumer;

    CipherOperationInstance() {
      exists(CipherGetInstanceToCipherOperationFlow::PathNode src, CipherGetInstanceCall getCipher |
        CipherGetInstanceToCipherOperationFlow::flowPath(src, sink) and
        src.getNode().asExpr() = getCipher and
        sink.getNode().asExpr() = doFinalize.getQualifier() and
        sink.getState().(CipherModeFlowState).getCipherOperationMode() = mode and
        this = doFinalize and
        consumer = getCipher.getAlgorithmArg()
      )
    }

    override Crypto::CipherOperationSubtype getCipherOperationSubtype() { result = mode }

    override Crypto::NonceArtifactConsumer getNonceConsumer() {
      result = sink.getState().(InitializedCipherModeFlowState).getInitCall().getNonceArg()
    }

    override Crypto::CipherInputConsumer getInputConsumer() {
      result = doFinalize.getMessageArg().asExpr()
    }

    override Crypto::AlgorithmConsumer getAlgorithmConsumer() { result = consumer }

    override Crypto::CipherOutputArtifactInstance getOutputArtifact() {
      result = doFinalize.getOutput()
    }
  }

  /**
   * Initialization vectors and other nonce artifacts
   */
  abstract class NonceParameterInstantiation extends ClassInstanceExpr {
    DataFlow::Node getOutputNode() { result.asExpr() = this }

    abstract DataFlow::Node getInputNode();
  }

  class IvParameterSpecInstance extends NonceParameterInstantiation {
    IvParameterSpecInstance() {
      this.(ClassInstanceExpr)
          .getConstructedType()
          .hasQualifiedName("javax.crypto.spec", "IvParameterSpec")
    }

    override DataFlow::Node getInputNode() {
      result.asExpr() = this.(ClassInstanceExpr).getArgument(0)
    }
  }

  // TODO: this also specifies the tag length for GCM
  class GCMParameterSpecInstance extends NonceParameterInstantiation {
    GCMParameterSpecInstance() {
      this.(ClassInstanceExpr)
          .getConstructedType()
          .hasQualifiedName("javax.crypto.spec", "GCMParameterSpec")
    }

    override DataFlow::Node getInputNode() {
      result.asExpr() = this.(ClassInstanceExpr).getArgument(1)
    }
  }

  class IvParameterSpecGetIvCall extends MethodCall {
    IvParameterSpecGetIvCall() {
      this.getMethod().hasQualifiedName("javax.crypto.spec", "IvParameterSpec", "getIV")
    }
  }

  predicate additionalFlowSteps(DataFlow::Node node1, DataFlow::Node node2) {
    exists(IvParameterSpecGetIvCall m |
      node1.asExpr() = m.getQualifier() and
      node2.asExpr() = m
    )
    or
    exists(NonceParameterInstantiation n |
      node1 = n.getInputNode() and
      node2 = n.getOutputNode()
    )
  }

  class NonceAdditionalFlowInputStep extends AdditionalFlowInputStep {
    DataFlow::Node output;

    NonceAdditionalFlowInputStep() { additionalFlowSteps(this, output) }

    override DataFlow::Node getOutput() { result = output }
  }

  /**
   * A data-flow configuration to track flow from a mode field access to
   * the mode argument of the `init` method of the `javax.crypto.Cipher` class.
   */
  private module JavaxCipherModeAccessToInitConfig implements DataFlow::ConfigSig {
    predicate isSource(DataFlow::Node src) {
      src.asExpr() instanceof JavaxCryptoCipherOperationModeAccess
    }

    predicate isSink(DataFlow::Node sink) {
      exists(CipherInitCall c | c.getModeArg() = sink.asExpr())
    }
  }

  module JavaxCipherModeAccessToInitFlow = DataFlow::Global<JavaxCipherModeAccessToInitConfig>;

  private predicate cipher_mode_str_to_cipher_mode_known(
    string mode, Crypto::CipherOperationSubtype cipher_mode
  ) {
    mode = "ENCRYPT_MODE" and cipher_mode instanceof Crypto::EncryptionSubtype
    or
    mode = "WRAP_MODE" and cipher_mode instanceof Crypto::WrapSubtype
    or
    mode = "DECRYPT_MODE" and cipher_mode instanceof Crypto::DecryptionSubtype
    or
    mode = "UNWRAP_MODE" and cipher_mode instanceof Crypto::UnwrapSubtype
  }

  class CipherInitCall extends MethodCall {
    CipherInitCall() { this.getCallee().hasQualifiedName("javax.crypto", "Cipher", "init") }

    /**
     * Returns the mode argument to the `init` method
     * that is used to determine the cipher operation mode.
     * Note this is the raw expr and not necessarily a direct access
     * of a mode. Use `getModeOrigin()` to get the field access origin
     * flowing to this argument, if one exists (is known).
     */
    Expr getModeArg() { result = this.getArgument(0) }

    JavaxCryptoCipherOperationModeAccess getModeOrigin() {
      exists(DataFlow::Node src, DataFlow::Node sink |
        JavaxCipherModeAccessToInitFlow::flow(src, sink) and
        src.asExpr() = result and
        this.getModeArg() = sink.asExpr()
      )
    }

    Crypto::CipherOperationSubtype getCipherOperationModeType() {
      if cipher_mode_str_to_cipher_mode_known(this.getModeOrigin().getField().getName(), _)
      then cipher_mode_str_to_cipher_mode_known(this.getModeOrigin().getField().getName(), result)
      else result instanceof Crypto::UnknownCipherOperationSubtype
    }

    Expr getKeyArg() {
      result = this.getArgument(1) and this.getMethod().getParameterType(1).hasName("Key")
    }

    Expr getNonceArg() {
      result = this.getArgument(2) and
      this.getMethod().getParameterType(2).hasName("AlgorithmParameterSpec")
    }
  }

  class CipherInitCallNonceArgConsumer extends Crypto::NonceArtifactConsumer instanceof Expr {
    CipherInitCallNonceArgConsumer() { this = any(CipherInitCall call).getNonceArg() }

    override DataFlow::Node getInputNode() { result.asExpr() = this }
  }

  class CipherInitCallKeyConsumer extends Crypto::ArtifactConsumer {
    CipherInitCallKeyConsumer() { this = any(CipherInitCall call).getKeyArg() }

    override DataFlow::Node getInputNode() { result.asExpr() = this }
  }

  class CipherMessageInputConsumer extends Crypto::CipherInputConsumer {
    CipherMessageInputConsumer() { this = any(CipherOperationCall call).getMessageArg().asExpr() }

    override DataFlow::Node getInputNode() { result.asExpr() = this }
  }

  class CipherOperationCallOutput extends CipherOutputArtifact {
    CipherOperationCallOutput() { this = any(CipherOperationCall call).getOutput() }

    override DataFlow::Node getOutputNode() { result.asExpr() = this }
  }
}
