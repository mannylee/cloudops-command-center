import { Link } from "react-router-dom";
import { ReactNode } from "react";

interface RouterLinkProps {
    href: string;
    children: ReactNode;
    [key: string]: any;
}

export default function RouterLink({ href, children, ...props }: RouterLinkProps) {
    return (
        <Link to={href} {...props}>
            {children}
        </Link>
    );
}