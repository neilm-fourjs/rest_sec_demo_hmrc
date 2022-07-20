
#SRV=https://test-www.tax.service.gov.uk
SRV=https://test-api.service.hmrc.gov.uk

cd $FGLDIR/web_utilities/services/openid-connect
source envoidc.sh
cd bin
fglrun ImportOAuth --import --authz $SRV/oauth/authorize --token $SRV/oauth/token $SRV

