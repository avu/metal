import javax.swing.*;

import java.awt.*;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.lang.reflect.InvocationTargetException;

public class Bubbles
{

    private static JPanel panel;
    private static float[] bx;
    private static float[] by;
    private static float[] vx;
    private static float[] vy;
    private static Color[][] bc;
    private static float[][] fr;
    private static Paint[] paint;

    private static float width = 800;
    private static float height = 800;
    private static float r = 25;
    private static int n;
    private static Font myFont = new Font("Serif", Font.BOLD, 16);
    private static double fps = 0;


    /**
     * The entry point of this sample
     * 
     * @param args Not used
     */
    public static void main(String args[]) throws InvocationTargetException, InterruptedException {
        SwingUtilities.invokeAndWait(new Runnable() {
            @Override
            public void run() {
                JFrame f = new JFrame();

                panel = new JPanel()
                {
                    @Override
                    protected void paintComponent(Graphics g) {

                        super.paintComponent(g);
                        long time = System.nanoTime();
                        Graphics2D g2d = (Graphics2D) g;
                        for (int i = 0; i < n; i++) {
                            RadialGradientPaint gp = new RadialGradientPaint(
                                    bx[i], by[i], r, fr[i],  bc[i]);
                           // g2d.setPaint(gp);
                          g2d.setColor(bc[i][0]);
                            g.fillOval((int)(bx[i] - r), (int)(by[i] - r), (int)(2*r), (int)(2*r));
                          //  g.fillRect((int)(bx[i] - r), (int)(by[i] - r), (int)(2*r), (int)(2*r));
                        }
                        time = System.nanoTime() - time;
                        fps = 1.0e9 / time;
                        g.setColor(Color.WHITE);
                        g.setFont(myFont);
                        g.drawString(Integer.toString((int)Math.round(fps)),20, 20);
                    }
                };

                panel.setPreferredSize(new Dimension((int)width, (int)height));
                panel.setBackground(Color.BLACK);
                f.add(panel);
                f.setDefaultCloseOperation(WindowConstants.EXIT_ON_CLOSE);
                f.pack();
                f.setVisible(true);
            }
        });
        n = 10;
        bx = new float[n];
        by = new float[n];
        vx = new float[n];
        vy = new float[n];
        bc = new Color[n][2];
        fr = new float[n][2];
        for (int i = 0; i < n; i++) {
            bx[i] = (float) (r + 0.1 + Math.random() * (width - 2*r - 0.2));
            by[i] = (float) (r + 0.1 + Math.random() * (height - 2*r - 0.2));
            vx[i] = 0.1f * (float) (Math.random() * 2*r - r);
            vy[i] = 0.1f * (float) (Math.random() * 2*r - r);
            bc[i][0] = new Color((float) Math.random(), (float) Math.random(), (float) Math.random());
            bc[i][1] = new Color((float) Math.random(), (float) Math.random(), (float) Math.random());
            fr[i] = new float[] {0.0f, 1.0f};
        }
        Timer timer = new Timer(10, new ActionListener() {
            @Override
            public void actionPerformed(ActionEvent e) {

                for (int i = 0; i < n; i++) {
                    bx[i] += vx[i];
                    if (bx[i] + r > width || bx[i] - r < 0) vx[i] = -vx[i];
                    by[i] += vy[i];
                    if (by[i] + r > height || by[i] - r < 0) vy[i] = -vy[i];
                }

                panel.getParent().repaint();

            }
        });
        timer.start();
    }
}
