import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.font.FontRenderContext;
import java.awt.font.GlyphVector;
import java.awt.font.LineBreakMeasurer;
import java.awt.font.TextAttribute;
import java.awt.font.TextLayout;
import java.awt.image.BufferedImage;
import java.text.AttributedString;

public class TestJava2D {
    public static void main(String[] args) {
        BufferedImage image = new BufferedImage(320, 100, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = image.createGraphics();
        Font font = new Font("Serif", Font.PLAIN, 18);
        FontRenderContext frc = g.getFontRenderContext();
        TextLayout layout = new TextLayout("hello java2d אבג", font, frc);
        GlyphVector gv = font.createGlyphVector(frc, "glyphs");
        AttributedString attributed = new AttributedString("line break measurer works");
        attributed.addAttribute(TextAttribute.FONT, font);
        LineBreakMeasurer lbm = new LineBreakMeasurer(attributed.getIterator(), frc);
        TextLayout firstLine = lbm.nextLayout(100f);
        layout.draw(g, 5, 35);
        firstLine.draw(g, 5, 70);
        g.dispose();
        int nonTransparent = 0;
        for (int y = 0; y < image.getHeight(); y++) {
            for (int x = 0; x < image.getWidth(); x++) {
                if ((image.getRGB(x, y) >>> 24) != 0) nonTransparent++;
            }
        }
        if (!java.awt.GraphicsEnvironment.isHeadless()) throw new AssertionError("not headless");
        if (layout.getAdvance() <= 0) throw new AssertionError("empty TextLayout");
        if (gv.getNumGlyphs() != 6) throw new AssertionError("bad GlyphVector");
        if (firstLine.getCharacterCount() <= 0) throw new AssertionError("bad LineBreakMeasurer");
        if (nonTransparent == 0) throw new AssertionError("BufferedImage draw produced no pixels");
        System.out.println("headless     = " + java.awt.GraphicsEnvironment.isHeadless());
        System.out.println("pixels       = " + nonTransparent);
    }
}
