<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:param name="glob" select="555"/>

  <xsl:template match="/">
    <xsl:value-of select="$glob"/>
    <xsl:variable name="glob" select="$glob + 1"/>
    <xsl:value-of select="$glob"/>

    <html>
      <xsl:if test="false()">
        fdfd</xsl:if>
      <head><title>Test of XSLT</title></head>
      <body bgcolor="white">
        <!-- <xsl:apply-templates/>  -->
        <xsl:variable name="num" select="2"/>
        <xsl:choose>
          <xsl:when test="$num = 1">
            num is <a href="http://localhost/{$num}"><xsl:value-of select="$num"/></a>
          </xsl:when>
          <xsl:when test="$num = 2">
            num is <a href="http://localhost/{$num}"><xsl:value-of select="$num"/></a>
          </xsl:when>
          <xsl:otherwise>
            num is neither 1 nor 2
          </xsl:otherwise>
        </xsl:choose>



        SOOOOOOOOO

        <xsl:for-each select="config/adress">
          <xsl:value-of select="age"/>
        </xsl:for-each>
        <!--<xsl:apply-templates select="config/adress"> 
          <xsl:sort select="age" data-type="number" order="ascending"/>
        </xsl:apply-templates>  -->



      </body>
    </html>
    <xsl:value-of select="$glob"/>
  </xsl:template>

  <xsl:template match="config/adress">
    <xsl:value-of select="$glob"/>
    <xsl:value-of select="name[@type = 'first']"/>
    <xsl:value-of select="name[@type = 'last']"/>

    <xsl:variable name="glob" select="5"/>
    <xsl:value-of select="$glob"/>
  </xsl:template>


  <!--  <xsl:include href="stylesheet2.xsl"/> -->

</xsl:stylesheet>
