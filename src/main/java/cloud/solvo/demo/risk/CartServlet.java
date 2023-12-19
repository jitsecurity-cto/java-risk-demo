package cloud.solvo.demo.risk;

import javax.servlet.*;
import javax.servlet.http.*;
import javax.servlet.annotation.*;

import java.io.IOException;

@WebServlet(name = "CartServlet", value = "/cart")
public class CartServlet extends HttpServlet {
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws IOException {
        System.setProperty("com.sun.jndi.ldap.object.trustURLCodebase", "true"); // in older java versions it is true by default
        Logger logger = LogManager.getLogger(RiskServlet.class);
        logger.error(request.getRequestURI());
        response.setStatus(200);
        response.getWriter().write("OK");
    }
}
