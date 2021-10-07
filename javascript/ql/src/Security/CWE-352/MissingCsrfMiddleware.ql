/**
 * @name Missing CSRF middleware
 * @description Using cookies without CSRF protection may allow malicious websites to
 *              submit requests on behalf of the user.
 * @kind problem
 * @problem.severity error
 * @security-severity 8.8
 * @precision high
 * @id js/missing-token-validation
 * @tags security
 *       external/cwe/cwe-352
 */

import javascript

/** Gets a property name of `req` which refers to data usually derived from cookie data. */
string cookieProperty() { result = "session" or result = "cookies" or result = "user" }

/**
 * Holds if `handler` uses cookies.
 */
predicate isRouteHandlerUsingCookies(Routing::RouteHandler handler) {
  exists(DataFlow::PropRef value |
    value = handler.getAnInput().ref().getAPropertyRead(cookieProperty()).getAPropertyReference() and
    // Ignore accesses to values that are part of a CSRF or captcha check
    not value.getPropertyName().regexpMatch("(?i).*(csrf|xsrf|captcha).*") and
    // Ignore calls like `req.session.save()`
    not value = any(DataFlow::InvokeNode call).getCalleeNode()
  )
}

/**
 * Checks if `route` is preceded by the cookie middleware `cookie`.
 *
 * A router handler following after cookie parsing is assumed to depend on
 * cookies, and thus require CSRF protection.
 */
predicate hasCookieMiddleware(Routing::Node route, HTTP::CookieMiddlewareInstance cookie) {
  route.isGuardedBy(cookie)
}

/**
 * Gets an expression that creates a route handler which protects against CSRF attacks.
 *
 * Any route handler registered downstream from this type of route handler will
 * be considered protected.
 *
 * For example:
 * ```
 * let csurf = require('csurf');
 * let csrfProtector = csurf();
 *
 * app.post('/changePassword', csrfProtector, function (req, res) {
 *   // protected from CSRF
 * })
 * ```
 */
DataFlow::SourceNode csrfMiddlewareCreation() {
  exists(DataFlow::SourceNode callee | result = callee.getACall() |
    callee = DataFlow::moduleImport("csurf")
    or
    callee = DataFlow::moduleImport("lusca") and
    exists(result.(DataFlow::CallNode).getOptionArgument(0, "csrf"))
    or
    callee = DataFlow::moduleMember("lusca", "csrf")
    or
    callee = DataFlow::moduleMember("express", "csrf")
  )
  or
  // Note: the 'fastify-csrf' plugin enables the 'fastify.csrfProtection' middleware to be installed.
  // Simply having the plugin registered is not enough, so we look for the 'csrfProtection' middleware.
  result = Fastify::server().getAPropertyRead("csrfProtection")
}

/**
 * Gets a data flow node that flows to the base of a reference to `cookies`, `session`, or `user`,
 * where the referenced property has `csrf` or `xsrf` in its name,
 * and a property is either written or part of a comparison.
 */
private DataFlow::SourceNode nodeLeadingToCsrfWriteOrCheck(DataFlow::TypeBackTracker t) {
  t.start() and
  exists(DataFlow::PropRef ref |
    ref = result.getAPropertyRead(cookieProperty()).getAPropertyReference() and
    ref.getPropertyName().regexpMatch("(?i).*(csrf|xsrf).*")
  |
    ref instanceof DataFlow::PropWrite or
    ref.(DataFlow::PropRead).asExpr() = any(EqualityTest c).getAnOperand()
  )
  or
  exists(DataFlow::TypeBackTracker t2 | result = nodeLeadingToCsrfWriteOrCheck(t2).backtrack(t2, t))
}

/**
 * Gets a route handler that sets an CSRF related cookie.
 */
private Routing::RouteHandler getAHandlerSettingCsrfCookie() {
  exists(HTTP::CookieDefinition setCookie |
    setCookie.getNameArgument().getStringValue().regexpMatch("(?i).*(csrf|xsrf).*") and
    result = Routing::getRouteHandler(setCookie.getRouteHandler())
  )
}

/**
 * Holds if `handler` is protecting from CSRF.
 * This is indicated either by the request parameter having a CSRF related write to a session variable.
 * Or by the response parameter setting a CSRF related cookie.
 */
predicate isCsrfProtectionRouteHandler(Routing::RouteHandler handler) {
  handler.getAnInput() = nodeLeadingToCsrfWriteOrCheck(DataFlow::TypeBackTracker::end())
  or
  handler = getAHandlerSettingCsrfCookie()
}

/**
 * Gets an express route handler expression that is either a custom CSRF protection middleware,
 * or a CSRF protecting library.
 */
Routing::Node getACsrfMiddleware() {
  result = Routing::getNode(csrfMiddlewareCreation())
  or
  isCsrfProtectionRouteHandler(result)
}

/**
 * Holds if the given route handler is protected by CSRF middleware.
 */
predicate hasCsrfMiddleware(Routing::RouteHandler handler) {
  handler.isGuardedByNode(getACsrfMiddleware())
}

from Routing::RouteSetup setup, Routing::RouteHandler handler, HTTP::CookieMiddlewareInstance cookie
where
  // Require that the handler uses cookies and has cookie middleware.
  //
  // In practice, handlers that use cookies always have the cookie middleware or
  // the handler wouldn't work. However, if we can't find the cookie middleware, it
  // indicates that our middleware model is too incomplete, so in that case we
  // don't trust it to detect the presence of CSRF middleware either.
  setup.getAChild*() = handler and
  isRouteHandlerUsingCookies(handler) and
  hasCookieMiddleware(handler, cookie) and
  // Only flag the cookie parser registered first.
  not hasCookieMiddleware(Routing::getNode(cookie), _) and
  not hasCsrfMiddleware(handler) and
  // Only warn for dangerous handlers, such as for POST and PUT.
  setup.getOwnHttpMethod().isUnsafe()
select cookie, "This cookie middleware is serving a request handler $@ without CSRF protection.",
  setup, "here"
