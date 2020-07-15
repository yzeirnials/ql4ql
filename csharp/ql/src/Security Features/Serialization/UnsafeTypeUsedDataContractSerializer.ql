/**
 * @name Unsafe type is used in data contract serializer
 * @description Unsafe type is used in data contract serializer. Please visit https://go.microsoft.com/fwlink/?linkid=2132227 for details."
 * @kind problem
 * @problem.severity error
 * @precision high
 * @id cs/dataset-serialization/unsafe-type-used-data-contract-serializer
 * @tags security
 */

import csharp
import DataSetSerialization

predicate isClassDependingOnDataSetOrTable( Class c ) {
  c instanceof DataSetOrTableRelatedClass
}

predicate xmlSerializerConstructorTypeParameter (Expr e) {
  exists (ObjectCreation oc, Constructor c |
    e = oc.getArgument(0) |
    c = oc.getTarget() and
    ( 
      c.getDeclaringType().hasQualifiedName("System.Xml.Serialization.XmlSerializer") or
      c.getDeclaringType().getABaseType*().hasQualifiedName("System.Xml.Serialization.XmlSerializer")
    )
  )
}

predicate unsafeDataContractTypeCreation (Expr e) {
  exists(MethodCall gt | 
    gt.getTarget().getName() = "GetType" and
    e = gt and
    isClassDependingOnDataSetOrTable(gt.getQualifier().getType())
  ) or
  isClassDependingOnDataSetOrTable(e.(TypeofExpr).getTypeAccess().getTarget())
}

class Conf extends DataFlow::Configuration {
  Conf() {
    this = "FlowToDataSerializerConstructor" 
  }
  
  override predicate isSource(DataFlow::Node node) {
    unsafeDataContractTypeCreation(node.asExpr())
    }
  
  override predicate isSink(DataFlow::Node node) {
      xmlSerializerConstructorTypeParameter (node.asExpr())
    }
}


from Conf conf, DataFlow::Node source, DataFlow::Node sink
where conf.hasFlow(source, sink)
select sink, "Unsafe type is used in data contract serializer. Make sure $@ comes from the trusted source.", source, source.toString()
