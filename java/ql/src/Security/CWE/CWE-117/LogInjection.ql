/**
 * @name Log Injection
 * @description Building log entries from user-controlled data may allow
 *              insertion of forged log entries by malicious users.
 * @kind path-problem
 * @problem.severity error
 * @security-severity 7.8
 * @precision medium
 * @id java/log-injection
 * @tags security
 *       external/cwe/cwe-117
 */

import java
import semmle.code.java.security.LogInjectionQuery
import DataFlow::PathGraph

from LogInjectionConfiguration cfg, DataFlow::PathNode source, DataFlow::PathNode sink
where cfg.hasFlowPath(source, sink)
select source.getNode(), source, sink, "This user-provided value flows to a $@.", sink.getNode(),
  "log entry"
