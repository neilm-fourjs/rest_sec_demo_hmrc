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


PRIVATE CONSTANT C_DATABASE = "oidc"

#
# Connect and initialize OpenID database
# NOTE: add database customization here
#
PUBLIC FUNCTION DBConnect()
  # Connect to DB
  TRY
    CONNECT TO C_DATABASE # USER "username" USING "password"
  CATCH
    RETURN FALSE 
  END TRY
  
  # Make sure to have committed read isolation level and wait for locks
  WHENEVER ERROR CONTINUE   # Ignore SQL errors if instruction not supported
  SET ISOLATION TO COMMITTED READ
  SET LOCK MODE TO WAIT 
  WHENEVER ERROR STOP
  RETURN TRUE
END FUNCTION

#
# Release and disconnect OpenID database
# NOTE: add database customization here
#
PUBLIC FUNCTION DBDisconnect()

  # Disconnect DB
  DISCONNECT C_DATABASE
  
END FUNCTION
