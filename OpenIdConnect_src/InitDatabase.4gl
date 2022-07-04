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
IMPORT FGL DBase

MAIN

  DISPLAY "Initializing OpenIDConnect database"

  IF NOT DBase.DBConnect() THEN
    DISPLAY "ERROR: unable to connect to database"
    EXIT PROGRAM(1)
  END IF
      
  DISPLAY "Initializing table: fjs_oidc_provider"
  WHENEVER ANY ERROR CONTINUE
  DROP TABLE fjs_oidc_provider;  
  WHENEVER ANY ERROR STOP
  CREATE TABLE fjs_oidc_provider (
    id                      SERIAL NOT NULL,
    issuer                  VARCHAR(255) NOT NULL, # REQUIRED. URL using the https scheme with no query or fragment component that the OP asserts as its Issuer Identifier. If Issuer discovery is supported (see Section 2), this value MUST be identical to the issuer value returned by WebFinger. This also MUST be identical to the iss Claim value in ID Tokens issued from this Issuer.
    authorization_endpoint  VARCHAR(255) NOT NULL, # REQUIRED. URL of the OP's OAuth 2.0 Authorization Endpoint [OpenID.Core].
    token_endpoint          VARCHAR(255) NOT NULL, # URL of the OP's OAuth 2.0 Token Endpoint [OpenID.Core]. This is REQUIRED unless only the Implicit Flow is used.
    userinfo_endpoint       VARCHAR(255),          # RECOMMENDED. URL of the OP's UserInfo Endpoint [OpenID.Core]. This URL MUST use the https scheme and MAY contain port, path, and query parameter components.
    jwks_uri                VARCHAR(255),          # REQUIRED. URL of the OP's JSON Web Key Set [JWK] document. This contains the signing key(s) the RP uses to validate signatures from the OP. The JWK Set MAY also contain the Server's encryption key(s), which are used by RPs to encrypt requests to the Server. When both signing and encryption keys are made available, a use (Key Use) parameter value is REQUIRED for all keys in the referenced JWK Set to indicate each key's intended usage. Although some algorithms allow the same key to be used for both signatures and encryption, doing so is NOT RECOMMENDED, as it is less secure. The JWK x5c parameter MAY be used to provide X.509 representations of keys provided. When used, the bare key values MUST still be present and MUST match those in the certificate. END RECORD
    end_session_endpoint    VARCHAR(255),          # OPTIONAL. URL to logout from OpenID Provider
    is_oauth2               BOOLEAN,
    UNIQUE (issuer)
  )
  DISPLAY "done..."

  DISPLAY "Initializing table: fjs_oidc_keys"
  WHENEVER ANY ERROR CONTINUE
  DROP TABLE   fjs_oidc_keys;
  WHENEVER ANY ERROR STOP
  CREATE TABLE fjs_oidc_keys (
    provider_id INTEGER NOT NULL,
    id VARCHAR(255) NOT NULL,
    type VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    PRIMARY KEY(provider_id, id)
  )
  DISPLAY "done..."
  
  DISPLAY "Initializing table: fjs_oidc_relaystate"
  WHENEVER ANY ERROR CONTINUE
  DROP TABLE fjs_oidc_relaystate;
  WHENEVER ANY ERROR STOP
  CREATE TABLE fjs_oidc_relaystate (
    uuid VARCHAR(36) NOT NULL,
    session_uuid VARCHAR(36) NOT NULL,
    path VARCHAR(255) NOT NULL,
    expires DATETIME YEAR TO SECOND NOT NULL,
    PRIMARY KEY(uuid, session_uuid)
  )
  DISPLAY "done..."
  
  DISPLAY "Initializing table: fjs_oidc_access"    
  WHENEVER ANY ERROR CONTINUE  
  DROP TABLE fjs_oidc_access;
  WHENEVER ANY ERROR STOP  
  CREATE TABLE fjs_oidc_access (
    uuid VARCHAR(36) NOT NULL,
    path VARCHAR(255) NOT NULL,
    remote_ip VARCHAR(255) NOT NULL,
    expires DATETIME YEAR TO SECOND NOT NULL,
    PRIMARY KEY(uuid)
  )
  DISPLAY "done..."    

  DISPLAY "Initializing table: fjs_oidc_access_attr"
  WHENEVER ANY ERROR CONTINUE  
  DROP TABLE fjs_oidc_access_attr;
  WHENEVER ANY ERROR STOP    
  CREATE TABLE fjs_oidc_access_attr (
    access_uuid VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    value TEXT,
    PRIMARY KEY(access_uuid, name)
  )
  DISPLAY "done..."    

  DISPLAY "Initializing table: fjs_oidc_session"
  WHENEVER ANY ERROR CONTINUE
  DROP TABLE fjs_oidc_session;
  WHENEVER ANY ERROR STOP
  CREATE TABLE fjs_oidc_session (
    uuid            VARCHAR(36) NOT NULL,
    provider_id     INTEGER NOT NULL,
    url             VARCHAR(255) NOT NULL,
    pub_id          VARCHAR(255) NOT NULL,
    secret_id       VARCHAR(255),
    scope           VARCHAR(255),
    authz           VARCHAR(255),
    sign_off        VARCHAR(255),
    end_url         VARCHAR(255),
    subject         VARCHAR(255),
    id_token        TEXT,
    session         VARCHAR(255),
    idp_logout_url  VARCHAR(255),
    expires         DATETIME YEAR TO SECOND NOT NULL,
    PRIMARY KEY(uuid, provider_id)
  )
  DISPLAY "done..."    

  CALL DBase.DBDisconnect()  
  
  DISPLAY "OpenIDConnect database completely initialized..."
  
END MAIN

