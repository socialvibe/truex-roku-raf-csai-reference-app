sub trace(msg_ as String, data_ = invalid)
    if m.loggerCat <> invalid then
        category_ = m.loggerCat
    else if m.top <> invalid then
        category_ = m.top.subtype()
    else
        category_ = "unknown"
    end if

    if type(data_) = "<uninitialized>" or data_ = invalid then
        ? "TRUE[X] >>> ";category_;" # ";msg_
    else
        ? "TRUE[X] >>> ";category_;" # ";msg_;" --- ";data_
    end if
end sub

sub traceEventMessage(msg as Object)
    if type(msg) = "roSGNodeEvent" then
        trace("trace() -- %s.%s".format(msg.GetRoSGNode().subtype(), msg.GetField()), msg.GetData())
    else
        trace("trace() -- %s".format(type(msg)), msg)
    end if
end sub
