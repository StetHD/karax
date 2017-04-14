# Simple lib to write JS UIs

import dom, vdom, jstrutils, components, jdict

export dom.Event, dom.cloneNode, dom

proc len(x: Node): int {.importcpp: "#.childNodes.length".}
proc `[]`(x: Node; idx: int): Element {.importcpp: "#.childNodes[#]".}

proc kout*[T](x: T) {.importc: "console.log", varargs.}
  ## the preferred way of debugging karax applications.

proc id*(e: Node): cstring {.importcpp: "#.id", nodecl.}
proc `id=`*(e: Node; x: cstring) {.importcpp: "#.id = #", nodecl.}
proc class*(e: Node): cstring {.importcpp: "#.className", nodecl.}
proc `class=`*(e: Node; v: cstring) {.importcpp: "#.className = #", nodecl.}

proc value*(e: Node): cstring {.importcpp: "#.value", nodecl.}
proc `value=`*(e: Node; v: cstring) {.importcpp: "#.value = #", nodecl.}

proc `disabled=`*(e: Node; v: bool) {.importcpp: "#.disabled = #", nodecl.}

proc getElementsByClass*(e: Node; name: cstring): seq[Node] {.
  importcpp: "#.getElementsByClassName(#)", nodecl.}

proc hasProp(e: Node; prop: cstring): bool {.importcpp: "(#.hasOwnProperty(#))".}
proc rawkey(e: Node): VKey {.importcpp: "#.karaxKey", nodecl.}
proc key*(e: Node): VKey =
  if e.hasProp"karaxKey": result = e.rawkey
  else: result = -1
proc `key=`*(e: Node; x: VKey) {.importcpp: "#.karaxKey = #", nodecl.}

type
  BoundingRect {.importc.} = object
    top, bottom, left, right: int

proc getBoundingClientRect(e: Node): BoundingRect {.
  importcpp: "getBoundingClientRect", nodecl.}
proc clientHeight(): int {.
  importcpp: "(window.innerHeight || document.documentElement.clientHeight)@", nodecl}
proc clientWidth(): int {.
  importcpp: "(window.innerWidth || document.documentElement.clientWidth)@", nodecl}

when false:
  proc pageYOffset(): int {.
    importcpp: "(window.pageYOffset)@", nodecl}
  proc pageXOffset(): int {.
    importcpp: "(window.pageXOffset)@", nodecl}

type
  Timeout* = ref object

var
  document* {.importc.}: Document
  toFocus: Node
  toFocusV: VNode

proc setFocus*(n: VNode) =
  toFocusV = n

proc isElementInViewport(el: Node; h: var int): bool =
  let rect = el.getBoundingClientRect()
  h = rect.bottom - rect.top
  result = rect.top >= 0 and rect.left >= 0 and
           rect.bottom <= clientHeight() and
           rect.right <= clientWidth()

proc vnodeToDom(n: VNode): Node =
  if n.kind == VNodeKind.text:
    result = document.createTextNode(n.text)
  elif n.kind == VNodeKind.vthunk:
    let x = callThunk(vcomponents[n.text], n)
    return vnodeToDom(x)
  elif n.kind == VNodeKind.dthunk:
    let x = callThunk(dcomponents[n.text], n)
    return x
  else:
    result = document.createElement(toTag[n.kind])
    for k in n:
      appendChild(result, vnodeToDom(k))
    # text is mapped to 'value':
    if n.text != nil:
      result.value = n.text
  if n.id != nil:
    result.id = n.id
  if n.class != nil:
    result.class = n.class
  if n.key >= 0:
    result.key = n.key
  for k, v in attrs(n):
    if v != nil:
      result.setAttr(k, v)
  let myn = n
  for e, h in items(n.events):
    proc wrapper(): proc (ev: Event) =
      let hh = h
      result = proc (ev: Event) =
        assert myn != nil
        hh(ev, myn)
    result.addEventListener(toEventName[e], wrapper())
  if n == toFocusV and toFocus.isNil:
    toFocus = result

proc same(n: VNode, e: Node): bool =
  if toTag[n.kind] == e.nodename:
    result = true
    if n.kind != VNodeKind.text:
      if e.len != n.len: return false
      for i in 0 ..< n.len:
        if not same(n[i], e[i]): return false

var
  dorender: proc (): VNode {.closure.}
  currentTree: VNode

proc setRenderer*(renderer: proc (): VNode) =
  dorender = renderer

proc setTimeout*(action: proc(); ms: int): Timeout {.importc, nodecl.}
proc clearTimeout*(t: Timeout) {.importc, nodecl.}
#proc targetElem*(e: Event): Element = cast[Element](e.target)

proc getElementById*(id: cstring): Element {.importc: "document.getElementById", nodecl.}

#proc getElementsByClassName*(cls: cstring): seq[Element] {.importc:
#  "document.getElementsByClassName", nodecl.}
#proc textContent(e: Node): cstring {.
#  importcpp: "#.textContent", nodecl.}

proc replaceById(id: cstring; newTree: Node) =
  let x = document.getElementById(id)
  x.parentNode.replaceChild(newTree, x)
  #newTree.id = id

proc equals(a, b: VNode): bool =
  if a.kind != b.kind: return false
  if a.id != b.id: return false
  if a.key != b.key: return false
  if a.kind == VNodeKind.text:
    if a.text != b.text: return false
  elif a.kind == VNodeKind.vthunk or a.kind == VNodeKind.dthunk:
    if a.text != b.text: return false
    if a.len != b.len: return false
    for i in 0..<a.len:
      if not equals(a[i], b[i]): return false
  if not sameAttrs(a, b): return false
  if a.class != b.class: return false
  # XXX test event listeners here?
  return true

proc equalsTree(a, b: VNode): bool =
  when false:
    # hashing is too fragile now with component support:
    if not a.validHash:
      a.calcHash()
    if not b.validHash:
      b.calcHash()
    return a.hash == b.hash
  else:
    return eq(a, b)

proc updateElement(parent, current: Node, newNode, oldNode: VNode) =
  if not equals(newNode, oldNode):
    let n = vnodeToDom(newNode)
    if parent == nil:
      replaceById("ROOT", n)
    else:
      parent.replaceChild(n, current)
  elif newNode.kind != VNodeKind.text:
    let newLength = newNode.len
    var oldLength = oldNode.len
    let minLength = min(newLength, oldLength)
    assert oldNode.kind == newNode.kind
    when defined(simpleDiff):
      for i in 0..min(newLength, oldLength)-1:
        updateElement(current, current[i], newNode[i], oldNode[i])
      if newLength > oldLength:
        for i in oldLength..newLength-1:
          current.appendChild(vnodeToDom(newNode[i]))
      elif oldLength > newLength:
        for i in countdown(oldLength-1, newLength):
          current.removeChild(current.lastChild)
    else:
      var commonPrefix = 0
      while commonPrefix < minLength and
          equalsTree(newNode[commonPrefix], oldNode[commonPrefix]):
        inc commonPrefix

      var oldPos = oldLength - 1
      var newPos = newLength - 1
      while oldPos >= commonPrefix and newPos >= commonPrefix and
          equalsTree(newNode[newPos], oldNode[oldPos]):
        dec oldPos
        dec newPos

      var pos = min(oldPos, newPos) + 1
      for i in commonPrefix..pos-1:
        updateElement(current, current.childNodes[i],
          newNode[i],
          oldNode[i])

      var nextChildPos = oldPos + 1
      while pos <= newPos:
        if nextChildPos == oldLength:
          current.appendChild(vnodeToDom(newNode[pos]))
        else:
          current.insertBefore(vnodeToDom(newNode[pos]), current.childNodes[nextChildPos])
        # added new Node, so old state of VDOM have one more Node
        inc oldLength
        inc pos
        inc nextChildPos

      for i in 0..oldPos-pos:
        current.removeChild(current.childNodes[pos])

when false:
  var drawTimeout: Timeout

proc dodraw() =
  let newtree = dorender()
  newtree.id = "ROOT"
  toFocus = nil
  if currentTree == nil:
    currentTree = newtree
    let asdom = vnodeToDom currentTree
    replaceById("ROOT", asdom)
  else:
    let olddom = document.getElementById("ROOT")
    updateElement(nil, olddom, newtree, currentTree)
    #assert same(newtree, document.getElementById("ROOT"))
    currentTree = newtree
  # now that it's part of the DOM, give it the focus:
  if toFocus != nil:
    toFocus.focus()

proc visibleKeys(e: Node; a, b: var VKey; h, count: var int) =
  # we only care about nodes that have a key:
  var hh = 0
  # do not recurse if there is a 'key' field already:
  if e.key >= 0:
    if isElementInViewport(e, hh):
      inc count
      inc h, hh
      a = min(a, e.key)
      b = max(b, e.key)
  else:
    for i in 0..<e.len:
      visibleKeys(e[i], a, b, h, count)

proc reqFrame(callback: proc()) {.importc: "window.requestAnimationFrame".}

proc redraw*() =
  # we buffer redraw requests:
  when false:
    if drawTimeout != nil:
      clearTimeout(drawTimeout)
    drawTimeout = setTimeout(dodraw, 30)
  elif true:
    reqFrame(dodraw)
  else:
    dodraw()

proc init*() =
  reqFrame(dodraw)

proc scrollTop*(e: Node): int {.importcpp: "#.scrollTop", nodecl.}
proc offsetHeight*(e: Node): int {.importcpp: "#.offsetHeight", nodecl.}
proc offsetTop*(e: Node): int {.importcpp: "#.offsetTop", nodecl.}

template onImpl(s) {.dirty.} =
  proc wrapper(ev: Event; n: VNode) =
    action(ev, n)
    redraw()
  addEventListener(e, s, wrapper)

proc setOnclick*(e: VNode; action: EventHandler) =
  onImpl EventKind.onclick

proc setOnDblclick*(e: VNode; action: EventHandler) =
  onImpl EventKind.ondblclick

proc setOnfocuslost*(e: VNode; action: EventHandler) =
  onImpl EventKind.onblur

proc setOnchanged*(e: VNode; action: EventHandler) =
  onImpl EventKind.onchange

proc setOnscroll*(e: VNode; action: EventHandler) =
  onImpl EventKind.onscroll

proc setOnscroll*(action: proc(min, max: VKey; diff: int)) =
  var oldY = window.pageYOffset

  proc wrapper(ev: Event) =
    let dir = window.pageYOffset - oldY
    if dir == 0: return

    var a = VKey high(int)
    var b = VKey 0
    var h, count: int
    document.visibleKeys(a, b, h, count)
    let avgh = h / count
    let diff = toInt(dir.float / avgh)
    if diff != 0:
      oldY = window.pageYOffset
      action(a, b, diff)
      redraw()

  document.addEventListener("scroll", wrapper)

proc setOnHashChange*(action: proc (hashPart: cstring)) =
  var onhashChange {.importc: "window.onhashchange".}: proc()
  var hashPart {.importc: "window.location.hash".}: cstring
  proc wrapper() =
    action(hashPart)
    redraw()
  onhashchange = wrapper

template nativeValue(ev): cstring = cast[Element](ev.target).value
template setNativeValue(ev, val) = cast[Element](ev.target).value = val

template keyeventBody() =
  n.value = nativeValue(ev)
  action(ev, n)
  setNativeValue(ev, n.value)
  redraw()

proc realtimeInput*(val: cstring; action: EventHandler): VNode =
  var timer: Timeout
  proc onkeyup(ev: Event; n: VNode) =
    proc wrapper() = keyeventBody()

    if timer != nil: clearTimeout(timer)
    timer = setTimeout(wrapper, 400)
  result = tree(VNodeKind.input, [(cstring"type", cstring"text")])
  result.value = val
  result.addEventListener(EventKind.onkeyup, onkeyup)

proc enterInput*(id, val: cstring; action: EventHandler): VNode =
  proc onkeyup(ev: Event; n: VNode) =
    if ev.keyCode == 13: keyeventBody()

  result = tree(VNodeKind.input, [(cstring"type", cstring"text")])
  result.id = id
  result.value = val
  result.addEventListener(EventKind.onkeyup, onkeyup)

proc setOnEnter*(n: VNode; action: EventHandler) =
  proc onkeyup(ev: Event; n: VNode) =
    if ev.keyCode == 13: keyeventBody()
  n.addEventListener(EventKind.onkeyup, onkeyup)

proc ajax(meth, url: cstring; headers: openarray[(cstring, cstring)];
          data: cstring;
          cont: proc (httpStatus: int; response: cstring)) =
  proc setRequestHeader(a, b: cstring) {.importc: "ajax.setRequestHeader".}
  {.emit: """
  var ajax = new XMLHttpRequest();
  ajax.open(`meth`,`url`,true);""".}
  for a, b in items(headers):
    setRequestHeader(a, b)
  {.emit: """
  ajax.onreadystatechange = function(){
    if(this.readyState == 4){
      if(this.status == 200){
        `cont`(this.status, this.responseText);
      } else {
        `cont`(this.status, this.statusText);
      }
    }
  }
  ajax.send(`data`);
  """.}

proc ajaxPut*(url: string; headers: openarray[(cstring, cstring)];
          data: cstring;
          cont: proc (httpStatus: int, response: cstring)) =
  ajax("PUT", url, headers, data, cont)

proc ajaxGet*(url: string; headers: openarray[(cstring, cstring)];
          cont: proc (httpStatus: int, response: cstring)) =
  ajax("GET", url, headers, nil, cont)

{.push stackTrace:off.}

proc setupErrorHandler*(useAlert=false) =
  ## Installs an error handler that transforms native JS unhandled
  ## exceptions into Nim based stack traces. If `useAlert` is false,
  ## the error message is put into the console, otherwise `alert`
  ## is called.
  proc stackTraceAsCstring(): cstring = cstring(getStackTrace())
  {.emit: """
  window.onerror = function(msg, url, line, col, error) {
    var x = "Error: " + msg + "\n" + `stackTraceAsCstring`()
    if (`useAlert`)
      alert(x);
    else
      console.log(x);
    var suppressErrorAlert = true;
    return suppressErrorAlert;
  };""".}

{.pop.}

proc prepend*(parent, kid: Element) =
  parent.insertBefore(kid, parent.firstChild)

proc loadScript*(jsfilename: cstring) =
  let body = getElementById("body")
  let s = document.createElement("script")
  s.setAttr "type", "text/javascript"
  s.setAttr "src", jsfilename
  body.prepend(s)
  redraw()