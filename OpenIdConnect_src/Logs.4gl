#
# FOURJS_START_COPYRIGHT(U,2015)
# Property of Four Js*
# (c) Copyright Four Js 2015, 2018. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#

IMPORT COM
IMPORT XML
IMPORT os

PUBLIC CONSTANT C_LOG_ERROR     = 1
PUBLIC CONSTANT C_LOG_DEBUG     = 2
PUBLIC CONSTANT C_LOG_MSG       = 3
PUBLIC CONSTANT C_LOG_ACCESS    = 4
PUBLIC CONSTANT C_LOG_SQLERROR  = 5

PRIVATE DEFINE pid  INTEGER
PRIVATE DEFINE level STRING 

DEFINE c base.channel

PRIVATE FUNCTION mkdir_recursive(path)
    DEFINE path STRING
    DEFINE dirname STRING, r INT
    IF os.Path.exists(path) THEN
       RETURN TRUE
    END IF
    LET dirname = os.Path.dirname(path)
    IF dirname == path THEN
      RETURN TRUE # no dirname to extract anymore
    END IF
    LET r = mkdir_recursive(dirname)
    IF NOT r THEN
       RETURN r
    END IF
    RETURN os.Path.mkdir(path)
END FUNCTION

PUBLIC FUNCTION LOG_INIT(lvl, path, f)
  DEFINE  f     STRING
  DEFINE  path  STRING 
  DEFINE  lvl   STRING 
  DEFINE  fullpath  STRING
  LET pid = fgl_getpid()
  LET level = lvl
  IF path IS NOT NULL THEN
    LET fullpath = path || "/log"
    IF NOT mkdir_recursive(fullpath) THEN
        DISPLAY "ERROR: Unable to create log file in ",fullpath
        EXIT PROGRAM(1)
    END IF
    CALL my_startlog(fullpath||"/"||f)
  ELSE
    CALL my_startlog(f)
  END IF
  IF level IS NOT NULL THEN
    CALL my_errorlog("MSGLOG : "||pid||" - [Logs] \"INIT\" with level='"||level||"' done")
  ELSE
    CALL my_errorlog("MSGLOG : "||pid||" - [Logs] \"INIT\" done")
  END IF
END FUNCTION

#
# LOG category : DEBUG or MSG passed as arg_val(1)
# By default : error and access messages are logged
#  MSG : logs also messages
#  DEBUG : logs everything
#
PUBLIC FUNCTION LOG_EVENT(cat,class,ev,msg)
  DEFINE cat  INTEGER
  DEFINE  ev  STRING
  DEFINE  class STRING 
  DEFINE  msg STRING  
  IF msg IS NULL THEN
    LET msg = "(null)"
  END IF
  CASE cat
    WHEN C_LOG_ERROR
      CALL my_errorlog("ERROR  : "||pid||" - ["||class||"] \""||ev||"\" "||msg)
    WHEN C_LOG_DEBUG
      IF level=="DEBUG" THEN
        CALL my_errorlog("DEBUG  : "||pid||" - ["||class||"] \""||ev||"\" "||msg)
      END IF
    WHEN C_LOG_SQLERROR
      CALL my_errorlog("SQLERR : "||pid||" - ["||class||"] \""||ev||"\" "||msg)
    WHEN C_LOG_MSG
      IF level=="MSG" OR level=="DEBUG" THEN 
        CALL my_errorlog("MSGLOG : "||pid||" - ["||class||"] \""||ev||"\" "||msg)
      END IF 
    WHEN C_LOG_ACCESS
      CALL my_errorlog("ACCESS : "||pid||" - ["||class||"] \""||ev||"\" "||msg)
  END CASE  
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION my_startlog( l_file STRING )
	LET c = base.Channel.create()
	CALL c.openFile(l_file,"a+")
	CALL c.writeLine(CURRENT||":Log Started")
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION my_errorlog( l_msg STRING )
	DISPLAY CURRENT||":"||l_msg.trim()
	CALL c.writeLine(CURRENT||":"||l_msg.trim())
END FUNCTION
  
