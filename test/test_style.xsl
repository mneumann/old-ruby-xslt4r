<xsl:stylesheet xmlns:xsl="http://www.fantasy-coders.de/xslt">

  <xsl:template match="/">
    <xsl:apply-templates select="lang/example"/> <!-- select="example[lang() = 'de']"/>  -->
  </xsl:template>

  <xsl:template match="lang/example">
    <xsl:value-of select="description
  </xsl:template>
</xsl:stylesheet>
