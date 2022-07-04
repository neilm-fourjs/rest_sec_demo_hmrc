#
# FOURJS_START_COPYRIGHT(U,2015)
# Property of Four Js*
# (c) Copyright Four Js 2015, 2022. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#

IMPORT com
IMPORT xml
IMPORT FGL Logs
IMPORT FGL Discovery

PUBLIC
TYPE IdPType  RECORD
  ID                      INTEGER,
  Issuer                  VARCHAR(255),
  authorization_endpoint  VARCHAR(255), # REQUIRED. URL of the OP's OAuth 2.0 Authorization Endpoint [OpenID.Core].
  token_endpoint          VARCHAR(255), # URL of the OP's OAuth 2.0 Token Endpoint [OpenID.Core]. This is REQUIRED unless only the Implicit Flow is used.
  userinfo_endpoint       VARCHAR(255), # RECOMMENDED. URL of the OP's UserInfo Endpoint [OpenID.Core]. This URL MUST use the https scheme and MAY contain port, path, and query parameter components.
  jwks_uri                VARCHAR(255), # REQUIRED. URL of the OP's JSON Web Key Set [JWK] document. This contains the signing key(s) the RP uses to validate signatures from the OP. The JWK Set MAY also contain the Server's encryption key(s), which are used by RPs to encrypt requests to the Server. When both signing and encryption keys are made available, a use (Key Use) parameter value is REQUIRED for all keys in the referenced JWK Set to indicate each key's intended usage. Although some algorithms allow the same key to be used for both signatures and encryption, doing so is NOT RECOMMENDED, as it is less secure. The JWK x5c parameter MAY be used to provide X.509 representations of keys provided. When used, the bare key values MUST still be present and MUST match those in the certificate. END RECORD
  end_session_endpoint    VARCHAR(255), # OPTIONAL. URL to logout from OpenID Provider
  is_oauth2               BOOLEAN
END RECORD


PUBLIC
FUNCTION GetIdP(p_id)
  DEFINE  p_id     INTEGER
  DEFINE  idp       IdPType
  WHENEVER ERROR CONTINUE
  SELECT *
    INTO idp.*
    FROM fjs_oidc_provider
    WHERE id == p_id
  WHENEVER ERROR STOP
  IF sqlca.sqlcode != 0 THEN
    INITIALIZE idp TO NULL
  END IF
  RETURN idp.*
END FUNCTION


#
# Retrieves OAuth end points from issuer and previously registered via ImportOAuth
#  or NULL in case of error

PUBLIC
FUNCTION GetOAuthFromIssuer(p_issuer)
  DEFINE  p_issuer  VARCHAR(255)
  DEFINE  idp       IdPType
  IF p_issuer IS NULL THEN
    RETURN idp.*
  END IF
  SELECT *
    INTO idp.*
    FROM fjs_oidc_provider
    WHERE issuer == p_issuer AND is_oauth2 == TRUE
  IF sqlca.sqlcode == NOTFOUND THEN
    INITIALIZE idp TO NULL
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"IdPManager","GetOAuthFromIssuer",SFMT("No issuer %1 found",p_issuer))
  ELSE
    CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"IdPManager","GetOAuthFromIssuer",SFMT("Found issuer %1",p_issuer))
  END IF
  RETURN idp.*
END FUNCTION

#
# Retrieves IDP end points from issuer
#  or NULL in case of error
#  If data are not in database, discovery for metadata is done for that account
#
PUBLIC
FUNCTION GetIdPFromIssuer(p_issuer)
  DEFINE  p_issuer  VARCHAR(255)
  DEFINE  idp       IdPType
  DEFINE  meta      Discovery.OpenIDMetadataType
  DEFINE  endpoint  STRING
  IF p_issuer IS NULL THEN
    RETURN idp.*
  END IF
  WHENEVER ERROR CONTINUE
  SELECT *
    INTO idp.*
    FROM fjs_oidc_provider
    WHERE issuer == p_issuer
  WHENEVER ERROR STOP
  IF sqlca.sqlcode == 0 THEN
    LET endpoint = idp.userinfo_endpoint
    IF endpoint.getLength()==0 THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"IdPManager","GetIdPIdFromEntityID","Reload issuer "||p_issuer)
      CALL Discovery.Discover(idp.Issuer) RETURNING meta.*
      IF meta.userinfo_endpoint IS NOT NULL THEN
        WHENEVER ERROR CONTINUE
          UPDATE fjs_oidc_provider
          SET userinfo_endpoint = meta.userinfo_endpoint
          WHERE id == idp.ID
        WHENEVER ERROR STOP
        IF SQLCA.sqlcode = 0 THEN
          LET idp.userinfo_endpoint = meta.userinfo_endpoint
        END IF
      END IF
    ELSE
      CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"IdPManager","GetIdPIdFromEntityID","Found issuer "||p_issuer)
    END IF
    # Return IDP data
    RETURN idp.*
  ELSE
    IF sqlca.sqlcode = NOTFOUND THEN
      # NOT FOUND, retrieve metadata from net
      CALL DiscoverIdPFromAccount(p_issuer) RETURNING idp.ID, meta.*
      IF idp.ID IS NOT NULL THEN
        LET idp.Issuer = meta.issuer
        LET idp.authorization_endpoint = meta.authorization_endpoint
        LET idp.token_endpoint = meta.token_endpoint
        LET idp.userinfo_endpoint = meta.userinfo_endpoint
        LET idp.jwks_uri = meta.jwks_uri
        LET idp.end_session_endpoint = meta.end_session_endpoint
        RETURN idp.*
      ELSE
        CALL Logs.LOG_EVENT(Logs.C_LOG_SQLERROR,"IdPManager","GetIdPIdFromEntityID","could not retrieve metadata")
        RETURN idp.*
      END IF
    END IF
  END IF
  CALL Logs.LOG_EVENT(Logs.C_LOG_SQLERROR,"IdPManager","GetIdPIdFromEntityID","could not retrieve IdP ID from database code="||SQLCA.SQLCODE)
  INITIALIZE idp TO NULL
  RETURN idp.*
END FUNCTION

#
# Retrieve IdP metadata and update database
#
PUBLIC FUNCTION DiscoverIdPFromAccount(p_account)
  DEFINE p_account  STRING
  DEFINE meta       Discovery.OpenIDMetadataType
  DEFINE uid        INTEGER
  CALL Discovery.Discover(p_account) RETURNING meta.*
  IF meta.issuer IS NOT NULL THEN
    # Insert meta into database
    WHENEVER ERROR CONTINUE
    INSERT INTO fjs_oidc_provider (issuer,authorization_endpoint,token_endpoint,userinfo_endpoint,jwks_uri,end_session_endpoint, is_oauth2 )
      VALUES (meta.issuer, meta.authorization_endpoint, meta.token_endpoint, meta.userinfo_endpoint, meta.jwks_uri, meta.end_session_endpoint, FALSE)
    WHENEVER ERROR STOP
    IF sqlca.sqlcode == 0 THEN
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"IdPManager","DiscoverIdPFromAccount","Metadata inserted into database")
      RETURN SQLCA.SQLERRD[2],meta.*
    ELSE
      # Retry a select, maybe a concurrent fglrun has inserted metadata
      CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"IdPManager","DiscoverIdPFromAccount","Retry metadata retrieval from database")
      WHENEVER ERROR CONTINUE
      SELECT id, issuer, authorization_endpoint, token_endpoint, userinfo_endpoint, jwks_uri, end_session_endpoint
        INTO uid, meta.Issuer, meta.authorization_endpoint, meta.token_endpoint, meta.userinfo_endpoint, meta.jwks_uri, meta.end_session_endpoint
        FROM fjs_oidc_provider
        WHERE issuer == p_account
      WHENEVER ERROR STOP
      IF SQLCA.sqlcode == 0 THEN
        RETURN uid, meta.*
      END IF
    END IF
  END IF
  INITIALIZE meta TO NULL
  RETURN NULL,meta.*
END FUNCTION
#
# Returns the X509 certificate of given IdP information from it's ID serial
#  @Note: if id is null and there is only one IdP in database, this one is returned
#         otherwise none is returned and IdP must be specified
PUBLIC
FUNCTION GetIdPX509(p_id,p_certid)
  DEFINE  p_id      INTEGER
  DEFINE  p_certid  VARCHAR(255)
  DEFINE  txt       TEXT
  DEFINE  cert      xml.CryptoX509
  IF p_id IS NULL THEN
    RETURN NULL
  END IF
  LOCATE txt IN MEMORY
  WHENEVER ERROR CONTINUE
  SELECT x509
    INTO txt
    FROM fjs_oidc_keys
    WHERE id = p_id AND key_id == p_certid
  WHENEVER ERROR STOP
  IF sqlca.sqlcode==0 THEN
    IF txt IS NOT NULL THEN
      LET cert = xml.CryptoX509.Create()
      CALL cert.loadFromString(txt)
    END IF
  ELSE
    CALL Logs.LOG_EVENT(Logs.C_LOG_SQLERROR,"IdPManager","GetIdP","could not retrieve IdP from database code="||SQLCA.SQLCODE)
  END IF
  FREE txt
  RETURN cert
END FUNCTION


