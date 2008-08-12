<xsl:stylesheet xmlns:xsl="http://www.fantasy-coders.de/xslt"
  xmlns:ruby="http://www.fantasy-coders.de/xslt/ruby"
  xmlns:lxslt="http://www.fantasy-coders.de/xslt/ext"
  xmlns:michael="michael.neumann.all"
  extension-element-prefixes="michael"
  >

  <lxslt:functions prefix="michael" object="Functions.new" convert="true">

    class Functions
      def initialize
        @txt = 34343 #"say hello"
      end

      def hello( context )
        @txt
      end

    end

  </lxslt:functions>

  <lxslt:elements prefix="michael" object="Elements.new">

    class Elements
      def initialize
        @txt = 34343 #"say hello"
      end

      def hello( *a )
        p "called"
        "hallllllllo"
      end

    end

  </lxslt:elements>



  <xsl:template name="mal-prob">
    1
    2
    3
    4
    5
    56
    6
    7
    87
    8
  </xsl:template>

  <xsl:template match="config">

    <xsl:call-template name="mal-prob"/>
    <xsl:call-template name="mal-prob"/>

    <ruby:eval>
      puts "haljasflkasjflasjfaslfjaslkj"
    </ruby:eval>

    <michael:hello/>

    <xsl:variable name="haha" select="555 + 222"/>

    <b> This is a configuration script </b>
    <!--    <xsl:value-of select="$haha + michael:hallo(1)" xmlns:michael="http://www.fantasy-coders.de/ruby/meth"/>  -->
    <xsl:value-of select="ruby:eval('puts %{hallo leute}; 4.5')"/> 
    <xsl:value-of select="michael:hello()"/> 

    <xsl:apply-templates mode="normal"/>
    <xsl:apply-templates mode="spec"/>
  </xsl:template>

  <xsl:template match="adress">
    Mode NONE
  </xsl:template>

  <xsl:template match="adress" mode="normal">
    Mode NORMAL
    <p>
    <xsl:value-of select="name[@type = 'first']"/>, <xsl:value-of select="name[@type = 'last']"/>
    <xsl:value-of select="age"/>
    </p>
  </xsl:template>

  <xsl:template match="adress" mode="spec">
    Mode SPEC
    <div>
    <xsl:value-of select="name[@type = 'first']"/>, <xsl:value-of select="name[@type = 'last']"/>
    <xsl:value-of select="age"/>
    </div>
  </xsl:template>


</xsl:stylesheet>
